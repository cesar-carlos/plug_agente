import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_email_address_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_smtp_profile_loader.dart';
import 'package:result_dart/result_dart.dart';

class EmailActionAdapter implements AgentActionAdapter {
  EmailActionAdapter({
    ActionPathValidator? pathValidator,
    IAgentActionSecretStore? secretStore,
    DateTime Function()? now,
  }) : _pathValidator = pathValidator ?? ActionPathValidator(),
       _smtpProfileLoader = AgentActionSmtpProfileLoader(secretStore: secretStore),
       _now = now ?? DateTime.now;

  final ActionPathValidator _pathValidator;
  final AgentActionSmtpProfileLoader _smtpProfileLoader;
  final DateTime Function() _now;

  @override
  AgentActionType get type => AgentActionType.email;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _resolveConfig(
      definition: definition,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
        safeMessage: definition.canRun
            ? 'Email action is ready to run.'
            : 'Email action is valid but not active.',
        redactedDiagnostics: {
          'recipient_count': resolved.config.to.length,
          'cc_count': resolved.config.cc.length,
          'bcc_count': resolved.config.bcc.length,
          'attachment_count': resolved.config.attachmentPaths.length,
          'uses_smtp_secret': !resolved.config.smtpProfileId.trim().startsWith('{'),
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final resolvedResult = await _resolveConfig(
      definition: definition,
      phase: 'execution_preflight',
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();
    final config = resolved.config;

    final redactedDiagnostics = <String, Object?>{
      'attachment_count': resolved.attachments.length,
    };

    for (final attachment in resolved.attachments) {
      final snapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'attachmentPaths',
        savedReference: attachment.reference,
        currentPath: attachment.validatedPath,
        diagnostics: redactedDiagnostics,
      );
      if (snapshotResult.isError()) {
        return Failure(snapshotResult.exceptionOrNull()!);
      }
    }

    final contextValidation = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextValidation.isError()) {
      return Failure(contextValidation.exceptionOrNull()!);
    }

    final smtpProfileResult = await _smtpProfileLoader.loadProfile(
      actionId: definition.id,
      smtpProfileReference: config.smtpProfileId,
    );
    if (smtpProfileResult.isError()) {
      return Failure(smtpProfileResult.exceptionOrNull()!);
    }

    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: resolved.redactedPreview,
        redactedDiagnostics: {
          ...redactedDiagnostics,
          'recipient_count': config.to.length,
          'cc_count': config.cc.length,
          'bcc_count': config.bcc.length,
          'context_path_extension': _extensionOf(request.contextPath),
          'uses_context_path': request.contextPath != null,
          'smtp_host': smtpProfileResult.getOrThrow().host,
          if (contextValidation.getOrThrow().path != null)
            'context_path': ActionPathPreflightMetadata.forValidatedPath(
              contextValidation.getOrThrow().path!,
            ),
          'attachment_paths': resolved.attachments
              .map(
                (attachment) => ActionPathPreflightMetadata.forValidatedPath(attachment.validatedPath),
              )
              .toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _resolveConfig(
      definition: definition,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    return Success(
      definition.copyWith(
        config: EmailActionConfig(
          smtpProfileId: resolved.config.smtpProfileId.trim(),
          from: resolved.config.from,
          to: resolved.config.to,
          cc: resolved.config.cc,
          bcc: resolved.config.bcc,
          subjectTemplate: resolved.config.subjectTemplate.trim(),
          bodyTemplate: resolved.config.bodyTemplate.trim(),
          attachmentPaths: resolved.attachments
              .map(
                (attachment) => _normalizedPathReference(
                  originalPath: attachment.reference,
                  validationPath: attachment.validatedPath,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Future<Result<_ResolvedEmailConfig>> _resolveConfig({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
  }) async {
    final config = definition.config;
    if (config is! EmailActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.email.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de e-mail e invalida.',
          },
        ),
      );
    }

    final smtpProfileId = config.smtpProfileId.trim();
    if (smtpProfileId.isEmpty || smtpProfileId.length > AgentActionEmailConstants.maxSmtpProfileIdLength) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'SMTP profile id is invalid.',
          context: {
            'action_id': definition.id,
            'field': 'smtpProfileId',
            'phase': phase,
            'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
            'user_message': 'Informe o nome do segredo SMTP desta acao.',
          },
        ),
      );
    }

    final fromResult = AgentActionEmailAddressValidator.validateAddress(
      actionId: definition.id,
      field: 'from',
      address: config.from,
      phase: phase,
    );
    if (fromResult.isError()) {
      return Failure(fromResult.exceptionOrNull()!);
    }

    final toResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'to',
      addresses: config.to,
      required: true,
      phase: phase,
    );
    if (toResult.isError()) {
      return Failure(toResult.exceptionOrNull()!);
    }

    final ccResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'cc',
      addresses: config.cc,
      required: false,
      phase: phase,
    );
    if (ccResult.isError()) {
      return Failure(ccResult.exceptionOrNull()!);
    }

    final bccResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'bcc',
      addresses: config.bcc,
      required: false,
      phase: phase,
    );
    if (bccResult.isError()) {
      return Failure(bccResult.exceptionOrNull()!);
    }

    final subject = config.subjectTemplate.trim();
    if (subject.isEmpty || subject.length > AgentActionEmailConstants.maxSubjectLength) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email subject template is invalid.',
          context: {
            'action_id': definition.id,
            'field': 'subjectTemplate',
            'phase': phase,
            'reason': AgentActionEmailConstants.subjectTooLongReason,
            'user_message': 'Informe um assunto valido para esta acao.',
          },
        ),
      );
    }

    final body = config.bodyTemplate.trim();
    if (body.isEmpty || body.length > AgentActionEmailConstants.maxBodyLength) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email body template is invalid.',
          context: {
            'action_id': definition.id,
            'field': 'bodyTemplate',
            'phase': phase,
            'reason': AgentActionEmailConstants.bodyTooLongReason,
            'user_message': 'Informe um corpo valido para esta acao.',
          },
        ),
      );
    }

    if (config.attachmentPaths.length > AgentActionEmailConstants.maxAttachments) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email attachment list exceeds the configured limit.',
          context: {
            'action_id': definition.id,
            'field': 'attachmentPaths',
            'phase': phase,
            'max_attachments': AgentActionEmailConstants.maxAttachments,
            'reason': AgentActionEmailConstants.tooManyAttachmentsReason,
            'user_message': 'A quantidade de anexos excede o limite permitido para esta acao.',
          },
        ),
      );
    }

    final attachments = <_ResolvedEmailAttachment>[];
    var totalAttachmentBytes = 0;
    for (final attachment in config.attachmentPaths) {
      final validation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'attachmentPaths',
        path: attachment,
        allowedExtensions: AgentActionEmailConstants.allowedAttachmentExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
        phase: phase,
        invalidPathUserMessage: 'Informe um caminho de anexo valido para esta acao.',
        notFoundUserMessage: 'Anexo nao encontrado. Verifique o caminho informado.',
        extensionNotAllowedUserMessage: 'Selecione um tipo de anexo permitido para esta acao.',
        notAllowedUserMessage: 'O anexo esta fora dos diretorios permitidos para esta acao.',
      );
      if (validation.isError()) {
        return Failure(validation.exceptionOrNull()!);
      }

      final validatedPath = validation.getOrThrow().path!;
      final sizeBytes = validatedPath.sizeBytes ?? 0;
      if (sizeBytes > AgentActionEmailConstants.maxAttachmentBytesPerFile) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Email attachment exceeds the per-file size limit.',
            context: {
              'action_id': definition.id,
              'field': 'attachmentPaths',
              'phase': phase,
              'size_bytes': sizeBytes,
              'max_bytes': AgentActionEmailConstants.maxAttachmentBytesPerFile,
              'reason': AgentActionEmailConstants.attachmentTooLargeReason,
              'user_message': 'Um dos anexos excede o tamanho maximo permitido.',
            },
          ),
        );
      }

      totalAttachmentBytes += sizeBytes;
      if (totalAttachmentBytes > AgentActionEmailConstants.maxTotalAttachmentBytes) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Email attachments exceed the total size limit.',
            context: {
              'action_id': definition.id,
              'field': 'attachmentPaths',
              'phase': phase,
              'total_bytes': totalAttachmentBytes,
              'max_bytes': AgentActionEmailConstants.maxTotalAttachmentBytes,
              'reason': AgentActionEmailConstants.totalAttachmentsTooLargeReason,
              'user_message': 'O total de anexos excede o limite permitido para esta acao.',
            },
          ),
        );
      }

      attachments.add(
        _ResolvedEmailAttachment(
          reference: attachment,
          validatedPath: validatedPath,
        ),
      );
    }

    final normalizedConfig = EmailActionConfig(
      smtpProfileId: smtpProfileId,
      from: fromResult.getOrThrow(),
      to: toResult.getOrThrow(),
      cc: ccResult.getOrThrow(),
      bcc: bccResult.getOrThrow(),
      subjectTemplate: subject,
      bodyTemplate: body,
      attachmentPaths: config.attachmentPaths,
    );

    return Success(
      _ResolvedEmailConfig(
        config: normalizedConfig,
        attachments: attachments,
        redactedPreview:
            'email smtp-profile=[REDACTED] from=[REDACTED] to=${normalizedConfig.to.length} recipients attachments=${attachments.length}',
      ),
    );
  }

  String? _extensionOf(String? path) {
    if (path == null) {
      return null;
    }
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return null;
    }
    return fileName.substring(dotIndex).toLowerCase();
  }

  AgentActionPathReference _normalizedPathReference({
    required AgentActionPathReference originalPath,
    required AgentActionValidatedPath validationPath,
  }) {
    return AgentActionPathReference(
      originalPath: validationPath.originalPath,
      canonicalPath: validationPath.canonicalPath,
      existsAtValidation: true,
      validatedAt: _now().toUtc(),
      validationHash: validationPath.contentHash ?? originalPath.validationHash,
      pathChangePolicy: originalPath.pathChangePolicy,
    );
  }
}

class _ResolvedEmailConfig {
  const _ResolvedEmailConfig({
    required this.config,
    required this.attachments,
    required this.redactedPreview,
  });

  final EmailActionConfig config;
  final List<_ResolvedEmailAttachment> attachments;
  final String redactedPreview;
}

class _ResolvedEmailAttachment {
  const _ResolvedEmailAttachment({
    required this.reference,
    required this.validatedPath,
  });

  final AgentActionPathReference reference;
  final AgentActionValidatedPath validatedPath;
}

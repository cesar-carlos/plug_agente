import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_email_address_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_email_template_renderer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_smtp_profile_loader.dart';
import 'package:plug_agente/infrastructure/actions/email_action_adapter.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionMailSender =
    Future<SendReport> Function(
      Message message,
      SmtpServer server, {
      Duration? timeout,
    });

class EmailActionMailerRunner implements AgentActionLocalRunner {
  EmailActionMailerRunner({
    ActionPathValidator? pathValidator,
    IAgentActionSecretStore? secretStore,
    AgentActionMailSender? mailSender,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _pathValidator = pathValidator ?? ActionPathValidator(),
       _secretStore = secretStore,
       _smtpProfileLoader = AgentActionSmtpProfileLoader(secretStore: secretStore),
       _mailSender = mailSender ?? send,
       _redactor = redactor;

  final ActionPathValidator _pathValidator;
  final IAgentActionSecretStore? _secretStore;
  final AgentActionSmtpProfileLoader _smtpProfileLoader;
  final AgentActionMailSender _mailSender;
  final AgentActionRedactor _redactor;

  @override
  AgentActionType get type => AgentActionType.email;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final config = definition.config;
    if (config is! EmailActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email runner received an invalid action config.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de e-mail e invalida.',
          },
        ),
      );
    }

    final adapter = EmailActionAdapter(
      pathValidator: _pathValidator,
      secretStore: _secretStore,
    );
    final preparedResult = await adapter.prepareExecution(
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }

    final contextPathResult = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextPathResult.isError()) {
      return Failure(contextPathResult.exceptionOrNull()!);
    }

    final smtpProfileResult = await _smtpProfileLoader.loadProfile(
      actionId: definition.id,
      smtpProfileReference: config.smtpProfileId,
    );
    if (smtpProfileResult.isError()) {
      return Failure(smtpProfileResult.exceptionOrNull()!);
    }
    final smtpProfile = smtpProfileResult.getOrThrow();

    final contextResult = await _loadTemplateContext(
      actionId: definition.id,
      contextValidation: contextPathResult.getOrThrow(),
    );
    if (contextResult.isError()) {
      return Failure(contextResult.exceptionOrNull()!);
    }
    final templateContext = contextResult.getOrThrow();

    final renderedSubjectResult = AgentActionEmailTemplateRenderer.render(
      actionId: definition.id,
      field: 'subjectTemplate',
      template: config.subjectTemplate,
      context: templateContext,
    );
    if (renderedSubjectResult.isError()) {
      return Failure(renderedSubjectResult.exceptionOrNull()!);
    }

    final renderedBodyResult = AgentActionEmailTemplateRenderer.render(
      actionId: definition.id,
      field: 'bodyTemplate',
      template: config.bodyTemplate,
      context: templateContext,
    );
    if (renderedBodyResult.isError()) {
      return Failure(renderedBodyResult.exceptionOrNull()!);
    }

    final fromResult = AgentActionEmailAddressValidator.validateAddress(
      actionId: definition.id,
      field: 'from',
      address: config.from,
      phase: 'execution_send',
    );
    if (fromResult.isError()) {
      return Failure(fromResult.exceptionOrNull()!);
    }

    final toResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'to',
      addresses: config.to,
      required: true,
      phase: 'execution_send',
    );
    if (toResult.isError()) {
      return Failure(toResult.exceptionOrNull()!);
    }

    final ccResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'cc',
      addresses: config.cc,
      required: false,
      phase: 'execution_send',
    );
    if (ccResult.isError()) {
      return Failure(ccResult.exceptionOrNull()!);
    }

    final bccResult = AgentActionEmailAddressValidator.validateRecipientList(
      actionId: definition.id,
      field: 'bcc',
      addresses: config.bcc,
      required: false,
      phase: 'execution_send',
    );
    if (bccResult.isError()) {
      return Failure(bccResult.exceptionOrNull()!);
    }

    final attachmentsResult = await _buildAttachments(
      definition: definition,
      config: config,
    );
    if (attachmentsResult.isError()) {
      return Failure(attachmentsResult.exceptionOrNull()!);
    }

    final message = Message()
      ..from = fromResult.getOrThrow()
      ..recipients = toResult.getOrThrow()
      ..ccRecipients = ccResult.getOrThrow()
      ..bccRecipients = bccResult.getOrThrow()
      ..subject = renderedSubjectResult.getOrThrow()
      ..text = renderedBodyResult.getOrThrow()
      ..attachments = attachmentsResult.getOrThrow();

    final smtpServer = SmtpServer(
      smtpProfile.host,
      port: smtpProfile.port,
      username: smtpProfile.username,
      password: smtpProfile.password,
      ssl: smtpProfile.ssl,
      allowInsecure: smtpProfile.allowInsecure,
      ignoreBadCertificate: smtpProfile.ignoreBadCertificate,
    );

    final startedAt = DateTime.now();
    try {
      await _mailSender(
        message,
        smtpServer,
        timeout: definition.policies.timeout.maxRuntime,
      );
      final finishedAt = DateTime.now();
      final recipientCount = toResult.getOrThrow().length + ccResult.getOrThrow().length + bccResult.getOrThrow().length;
      final stdoutText = _redactor.redactText(
        'Email sent to $recipientCount recipient(s) via ${smtpProfile.host}:${smtpProfile.port}.',
      );

      return Success(
        AgentActionProcessResult(
          status: AgentActionExecutionStatus.succeeded,
          pid: 0,
          exitCode: 0,
          processStartedAt: startedAt,
          finishedAt: finishedAt,
          processExecutable: 'smtp://${smtpProfile.host}:${smtpProfile.port}',
          processArgumentCount: recipientCount,
          processCommandPreview: preparedResult.getOrThrow().redactedCommandPreview,
          stdout: definition.policies.capture.captureStdout
              ? AgentActionCapturedOutput(
                  text: stdoutText,
                  isCaptured: true,
                )
              : AgentActionCapturedOutput.disabled,
          stderr: AgentActionCapturedOutput.disabled,
          contextHash: contextPathResult.getOrThrow().path?.contentHash,
          redactionApplied: true,
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to send email action.',
          cause: error,
          code: AgentActionFailureCode.runtimeError,
          context: {
            'action_id': definition.id,
            'execution_id': executionId,
            'phase': 'smtp_send',
            'smtp_host': smtpProfile.host,
            'smtp_port': smtpProfile.port,
            'reason': AgentActionEmailConstants.smtpSendFailedReason,
            'user_message':
                'Nao foi possivel enviar o e-mail. Verifique o perfil SMTP, destinatarios e conectividade.',
          },
        ),
      );
    }
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Failure(
      ActionNotFoundFailure.withContext(
        message: 'Email action execution is not cancellable after send starts.',
        code: AgentActionFailureCode.processNotActive,
        context: {
          'execution_id': executionId,
          'expected_pid': expectedPid,
          'phase': 'cancel',
          'reason': AgentActionProcessConstants.processNotActiveReason,
          'user_message': 'Acoes de e-mail nao possuem processo ativo para cancelamento.',
        },
      ),
    );
  }

  Future<Result<Map<String, Object?>>> _loadTemplateContext({
    required String actionId,
    required AgentActionPathValidation contextValidation,
  }) async {
    final validatedPath = contextValidation.path;
    if (validatedPath == null) {
      return const Success(<String, Object?>{});
    }

    final content = await File(validatedPath.canonicalPath).readAsString();
    return AgentActionEmailTemplateRenderer.parseContextJson(
      actionId: actionId,
      content: content,
    );
  }

  Future<Result<List<Attachment>>> _buildAttachments({
    required AgentActionDefinition definition,
    required EmailActionConfig config,
  }) async {
    final attachments = <Attachment>[];
    for (final attachment in config.attachmentPaths) {
      final validation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'attachmentPaths',
        path: attachment,
        allowedExtensions: AgentActionEmailConstants.allowedAttachmentExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
        phase: 'execution_send',
      );
      if (validation.isError()) {
        return Failure(validation.exceptionOrNull()!);
      }

      final validatedPath = validation.getOrThrow().path!;
      attachments.add(
        FileAttachment(
          File(validatedPath.canonicalPath),
        ),
      );
    }

    return Success(attachments);
  }
}

import 'dart:convert';

import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_smtp_profile.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionSmtpProfileLoader {
  const AgentActionSmtpProfileLoader({
    IAgentActionSecretStore? secretStore,
  }) : _secretStore = secretStore;

  final IAgentActionSecretStore? _secretStore;

  Future<Result<AgentActionSmtpProfile>> loadProfile({
    required String actionId,
    required String smtpProfileReference,
    String phase = 'execution_preflight',
  }) async {
    final trimmed = smtpProfileReference.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'SMTP profile reference cannot be empty.',
          context: {
            'action_id': actionId,
            'field': 'smtpProfileId',
            'phase': phase,
            'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
            'user_message': 'Informe o perfil SMTP desta acao.',
          },
        ),
      );
    }

    if (trimmed.startsWith('{')) {
      return _parseProfileJson(
        actionId: actionId,
        rawJson: trimmed,
        phase: phase,
      );
    }

    final store = _secretStore;
    if (store == null || !store.isAvailable) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Secret store is unavailable for SMTP profile loading.',
          code: AgentActionFailureCode.secretUnavailable,
          context: {
            'action_id': actionId,
            'field': 'smtpProfileId',
            'phase': phase,
            'reason': AgentActionValidationConstants.secretStoreUnavailableReason,
            'user_message': 'O armazenamento seguro nao esta disponivel para carregar o perfil SMTP.',
          },
        ),
      );
    }

    final rawSecret = await store.readSecret(trimmed);
    if (rawSecret == null || rawSecret.trim().isEmpty) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'SMTP profile secret was not found.',
          code: AgentActionFailureCode.secretUnavailable,
          context: {
            'action_id': actionId,
            'field': 'smtpProfileId',
            'secret_name': trimmed,
            'phase': phase,
            'reason': AgentActionEmailConstants.smtpProfileNotFoundReason,
            'user_message': 'Perfil SMTP nao encontrado no armazenamento seguro deste agente.',
          },
        ),
      );
    }

    return _parseProfileJson(
      actionId: actionId,
      rawJson: rawSecret,
      phase: phase,
    );
  }

  Result<AgentActionSmtpProfile> _parseProfileJson({
    required String actionId,
    required String rawJson,
    required String phase,
  }) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'SMTP profile JSON must be an object.',
            context: {
              'action_id': actionId,
              'field': 'smtpProfileId',
              'phase': phase,
              'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
              'user_message': 'O perfil SMTP precisa ser um objeto JSON valido.',
            },
          ),
        );
      }

      final host = decoded['host'];
      if (host is! String || host.trim().isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'SMTP profile host is required.',
            context: {
              'action_id': actionId,
              'field': 'smtpProfileId.host',
              'phase': phase,
              'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
              'user_message': 'O perfil SMTP precisa informar o host.',
            },
          ),
        );
      }

      final portValue = decoded['port'];
      final port = switch (portValue) {
        final int value => value,
        final String value => int.tryParse(value.trim()),
        _ => null,
      };
      if (port == null || port <= 0 || port > 65535) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'SMTP profile port is invalid.',
            context: {
              'action_id': actionId,
              'field': 'smtpProfileId.port',
              'phase': phase,
              'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
              'user_message': 'O perfil SMTP precisa informar uma porta valida.',
            },
          ),
        );
      }

      final username = decoded['username'];
      final password = decoded['password'];
      return Success(
        AgentActionSmtpProfile(
          host: host.trim(),
          port: port,
          username: username is String && username.trim().isNotEmpty ? username.trim() : null,
          password: password is String && password.isNotEmpty ? password : null,
          ssl: decoded['ssl'] == true,
          allowInsecure: decoded['allowInsecure'] == true,
          ignoreBadCertificate: decoded['ignoreBadCertificate'] == true,
        ),
      );
    } on FormatException catch (error) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'SMTP profile JSON is invalid.',
          cause: error,
          context: {
            'action_id': actionId,
            'field': 'smtpProfileId',
            'phase': phase,
            'reason': AgentActionEmailConstants.invalidSmtpProfileReason,
            'user_message': 'O perfil SMTP nao e um JSON valido.',
          },
        ),
      );
    }
  }
}

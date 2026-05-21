import 'dart:convert';

import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract final class AgentActionEmailTemplateRenderer {
  static final RegExp _tokenPattern = RegExp(r'\{\{([^{}]+)\}\}');

  static Result<String> render({
    required String actionId,
    required String field,
    required String template,
    Map<String, Object?> context = const <String, Object?>{},
    String phase = 'execution_preflight',
  }) {
    final rendered = template.replaceAllMapped(_tokenPattern, (match) {
      final key = match.group(1)?.trim();
      if (key == null || key.isEmpty) {
        return match.group(0)!;
      }

      final value = _lookupContextValue(context, key);
      if (value == null) {
        return match.group(0)!;
      }

      return value;
    });

    if (_tokenPattern.hasMatch(rendered)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email template still contains unresolved tokens.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': AgentActionEmailConstants.unresolvedTemplateTokenReason,
            'user_message':
                'O modelo de e-mail ainda contem variaveis nao resolvidas. Verifique o arquivo de contexto.',
          },
        ),
      );
    }

    return Success(rendered);
  }

  static Result<Map<String, Object?>> parseContextJson({
    required String actionId,
    required String content,
    String phase = 'execution_preflight',
  }) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Email context JSON must be an object.',
            context: {
              'action_id': actionId,
              'phase': phase,
              'reason': AgentActionEmailConstants.unresolvedTemplateTokenReason,
              'user_message': 'O arquivo de contexto precisa ser um objeto JSON.',
            },
          ),
        );
      }

      return Success(Map<String, Object?>.from(decoded));
    } on FormatException catch (error) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Email context JSON is invalid.',
          cause: error,
          context: {
            'action_id': actionId,
            'phase': phase,
            'reason': AgentActionEmailConstants.unresolvedTemplateTokenReason,
            'user_message': 'O arquivo de contexto JSON e invalido.',
          },
        ),
      );
    }
  }

  static String? _lookupContextValue(Map<String, Object?> context, String key) {
    final segments = key.split('.').map((segment) => segment.trim()).where((segment) => segment.isNotEmpty);
    Object? current = context;
    for (final segment in segments) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }

    if (current == null) {
      return null;
    }
    if (current is String) {
      return current;
    }
    if (current is num || current is bool) {
      return current.toString();
    }

    return null;
  }
}

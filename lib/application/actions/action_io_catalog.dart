import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';

/// Cursors reveal no action ID and expire when the runtime restarts.
final class ActionIoCatalog {
  ActionIoCatalog(this.repository, this.authorization, this.eligible);

  final IAgentActionRepository repository;
  final ActionIoAuthorization authorization;
  final Future<bool> Function(AgentActionDefinition) eligible;
  final Hmac _cursorMac = Hmac(sha256, List<int>.generate(32, (_) => Random.secure().nextInt(256)));

  String _cursor(String agent, String client, String id) =>
      _cursorMac.convert(utf8.encode(jsonEncode([agent, client, id]))).toString();

  Future<Map<String, dynamic>> page({
    required String agentId,
    required String credential,
    int pageSize = 20,
    String? cursor,
  }) async {
    if (pageSize < 1 || pageSize > 50) throw ActionValidationFailure('Invalid catalog page size.');
    final principal = (await authorization.authorizeCatalogPage(credential: credential, agentId: agentId)).getOrThrow();
    final definitions = [...(await repository.listDefinitions()).getOrThrow()]..sort((a, b) => a.id.compareTo(b.id));
    var start = 0;
    if (cursor != null) {
      final boundary = definitions.indexWhere((item) => _cursor(agentId, principal.clientId, item.id) == cursor);
      if (boundary < 0) {
        throw ActionValidationFailure.withContext(
          message: 'Invalid or expired catalog cursor. Restart the listing.',
          code: 'ACTION_CATALOG_INVALID_CURSOR',
          context: {'origin': 'agent', 'recovery': 'restart_listing', 'effects_possible': false},
        );
      }
      start = boundary + 1;
    }
    final actions = <Map<String, dynamic>>[];
    String? next;
    for (final action in definitions.skip(start)) {
      final access = await authorization.authorize(
        credential: credential,
        agentId: agentId,
        actionId: action.id,
        ownerClientId: principal.clientId,
        operation: ActionIoOperation.listAvailable,
      );
      final failure = access.exceptionOrNull();
      if (failure is ActionAuthorizationFailure && failure.context['reason'] == 'scope_or_action_denied') continue;
      access.getOrThrow();
      if (!await eligible(action)) continue;
      final triggers = (await repository.listTriggers(
        actionId: action.id,
        isEnabled: true,
        types: {AgentActionTriggerType.remote},
      )).getOrThrow();
      if (triggers.isEmpty) continue;
      if (actions.length == pageSize) {
        next = _cursor(agentId, principal.clientId, actions.last['action_id'] as String);
        break;
      }
      actions.add({
        'action_id': action.id,
        'name': action.name,
        'io_eligible': true,
        'trigger_ids': triggers.map((trigger) => trigger.id).toList()..sort(),
        'public_description': action.policies.remote.publicDescription.isEmpty
            ? null
            : action.policies.remote.publicDescription,
        'stdin_description': action.policies.remote.stdinDescription.isEmpty
            ? null
            : action.policies.remote.stdinDescription,
        'stdout_description': action.policies.remote.stdoutDescription.isEmpty
            ? null
            : action.policies.remote.stdoutDescription,
        'stderr_description': action.policies.remote.stderrDescription.isEmpty
            ? null
            : action.policies.remote.stderrDescription,
      });
    }
    for (final action in actions) {
      (await authorization.authorize(
        credential: credential,
        agentId: agentId,
        ownerClientId: principal.clientId,
        actionId: action['action_id'] as String,
        operation: ActionIoOperation.listAvailable,
      )).getOrThrow();
    }
    (await authorization.authorizeCatalogPage(credential: credential, agentId: agentId)).getOrThrow();
    return {'actions': actions, 'next_cursor': next};
  }
}

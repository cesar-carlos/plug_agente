import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';

/// Provisions only the explicitly selected private desktop execution fixture.
Future<void> provisionDesktopActionIo(
  String root, {
  required String agentId,
  required String clientId,
  String? secondClientId,
  String? thirdClientId,
}) async {
  final directory = Directory(root).resolveSymbolicLinksSync();
  if (Directory(directory).parent.path != Directory.systemTemp.resolveSymbolicLinksSync() ||
      !p.basename(directory).startsWith('sql-operation-bootstrap-') ||
      Directory.current.resolveSymbolicLinksSync() != directory) {
    throw StateError('Private desktop provisioning scope is invalid.');
  }
  final output = File(p.join(directory, 'action-io-caller.json'));
  if (output.existsSync()) throw StateError('Desktop provisioning requires a fresh profile.');
  final repository = getIt<IAgentActionRepository>();
  const snapshotter = AgentActionDefinitionSnapshotter();
  var action = AgentActionDefinition(
    id: 'desktop-byte-echo',
    name: 'Private binary echo',
    state: AgentActionState.active,
    config: ExecutableActionConfig(
      executablePath: AgentActionPathReference(
        originalPath: '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      ),
      arguments: const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$i=[Console]::OpenStandardInput();$o=[Console]::OpenStandardOutput();$e=[Console]::OpenStandardError();$b=New-Object byte[] 65536;while(($n=$i.Read($b,0,$b.Length)) -gt 0){$o.Write($b,0,$n);$o.Flush();$e.Write($b,0,$n);$e.Flush()}',
      ],
    ),
    policies: AgentActionDefinitionPolicies(
      remote: AgentActionRemotePolicy(isEnabled: true, allowFaithfulIo: true, approvedAt: DateTime.now().toUtc()),
    ),
  );
  action = action.copyWith(
    policies: action.policies.copyWith(
      remote: action.policies.remote.copyWith(riskFingerprint: snapshotter.riskFingerprint(action)),
    ),
  );
  (await repository.saveDefinition(action)).getOrThrow();
  (await repository.saveTrigger(
    const AgentActionTrigger(
      id: 'desktop-byte-echo-trigger',
      actionId: 'desktop-byte-echo',
      type: AgentActionTriggerType.remote,
    ),
  )).getOrThrow();
  final createToken = CreateClientToken(getIt<IClientTokenRepository>());
  const scopes = [
    'agent_actions.io',
    'agent_actions.run',
    'agent_actions.validate_run',
    'agent_actions.read_execution',
    'agent_actions.cancel',
  ];
  final credential = (await createToken.createWithIdentity(
    ClientTokenCreateRequest(
      clientId: clientId,
      agentId: agentId,
      name: 'Private desktop caller',
      allTables: false,
      allViews: false,
      rules: [],
      payload: {
        'agent_action_scopes': scopes,
      },
    ),
  )).getOrThrow();
  final foreignCredential = (await createToken.createWithIdentity(
    ClientTokenCreateRequest(
      clientId: secondClientId ?? '$clientId-foreign',
      agentId: agentId,
      name: 'Private desktop foreign caller',
      allTables: false,
      allViews: false,
      rules: [],
      payload: {
        'agent_action_scopes': scopes,
      },
    ),
  )).getOrThrow();
  final thirdCredential = thirdClientId == null
      ? null
      : (await createToken.createWithIdentity(
          ClientTokenCreateRequest(
            clientId: thirdClientId,
            agentId: agentId,
            name: 'Private desktop third caller',
            allTables: false,
            allViews: false,
            rules: [],
            payload: {
              'agent_action_scopes': scopes,
            },
          ),
        )).getOrThrow();
  await output.writeAsString(
    jsonEncode({
      'actionId': action.id,
      'credential': credential.tokenValue,
      'foreignCredential': foreignCredential.tokenValue,
      if (thirdCredential != null) 'thirdCredential': thirdCredential.tokenValue,
    }),
    flush: true,
  );
}

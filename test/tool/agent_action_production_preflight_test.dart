import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/agent_action_production_preflight.dart';

void main() {
  group('countProductionComObjectRegistrations', () {
    test('should ignore commented registrations', () {
      const source = '''
return const <RegisteredComObjectInvocation>[
  // RegisteredComObjectInvocation(progId: 'X', memberName: 'Y', handler: h),
  RegisteredComObjectInvocation(
    progId: 'A',
    memberName: 'B',
    handler: handler,
  ),
];
''';

      expect(countProductionComObjectRegistrations(source), 1);
    });
  });

  group('evaluateAgentActionProductionPreflight', () {
    test('should warn when COM stub is enabled without production handlers', () {
      final result = evaluateAgentActionProductionPreflight(
        comRegistrationsSource: 'return const <RegisteredComObjectInvocation>[];',
        fileEnv: <String, String>{
          'AGENT_ACTION_COM_STUB_ENABLED': 'true',
          'AGENT_ACTION_COM_STUB_PROG_ID': 'AgentAction.Test',
          'AGENT_ACTION_COM_STUB_MEMBER_NAME': 'Ping',
        },
        projectRoot: '.',
      );

      expect(result.isSuccess, isTrue);
      expect(result.warnings, isNotEmpty);
      expect(result.failures, isEmpty);
    });

    test('should fail when strict COM handlers required but none configured', () {
      final result = evaluateAgentActionProductionPreflight(
        comRegistrationsSource: 'return const <RegisteredComObjectInvocation>[];',
        fileEnv: const <String, String>{},
        projectRoot: '.',
        strictComHandlers: true,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failures, isNotEmpty);
    });

    test('should fail when live RPC tests enabled but Hub env is incomplete', () {
      final result = evaluateAgentActionProductionPreflight(
        comRegistrationsSource: 'return const <RegisteredComObjectInvocation>[];',
        fileEnv: const <String, String>{
          'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
        },
        projectRoot: '.',
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failures.single,
        contains('RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS'),
      );
    });

    test('should fail when live RPC tests enabled and Hub signing preflight blocks', () {
      final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
      final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
      final token = 'h.$payload.s';

      final result = evaluateAgentActionProductionPreflight(
        comRegistrationsSource: 'return const <RegisteredComObjectInvocation>[];',
        fileEnv: <String, String>{
          'RUN_LIVE_HUB_TESTS': 'true',
          'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
          'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
          'E2E_HUB_URL': 'https://hub.example.com',
          'E2E_HUB_TOKEN': token,
          'PAYLOAD_SIGNING_KEY_ID': 'e2e-dev',
          'PAYLOAD_SIGNING_KEY': 'secret',
        },
        projectRoot: '.',
      );

      expect(result.isSuccess, isFalse);
      expect(result.failures.any((String s) => s.contains('e2e-dev')), isTrue);
    });
  });
}

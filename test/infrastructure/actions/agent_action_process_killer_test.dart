import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:test/test.dart';
import 'package:win32/win32.dart';

void main() {
  group('AgentActionProcessKiller', () {
    test('should return false when orphan kill pid is not positive', () {
      expect(
        AgentActionProcessKiller.tryKillOrphanByPid(
          executionId: 'exec-1',
          pid: 0,
        ),
        isFalse,
      );
    });

    test('should treat Windows and Unix access denied codes as permission errors', () {
      expect(AgentActionProcessKiller.isOsAccessDeniedErrorCode(ERROR_ACCESS_DENIED), isTrue);
      expect(AgentActionProcessKiller.isOsAccessDeniedErrorCode(13), isTrue);
      expect(AgentActionProcessKiller.isOsAccessDeniedErrorCode(2), isFalse);
      expect(AgentActionProcessKiller.isOsAccessDeniedErrorCode(null), isFalse);
    });
  });
}

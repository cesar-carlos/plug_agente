import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_lifetime_checker.dart';

void main() {
  group('WindowsProcessLifetimeChecker', () {
    test('should use injected predicate when provided', () async {
      final checker = WindowsProcessLifetimeChecker(
        processRunningPredicate: (pid) async => pid == 42,
      );

      expect(await checker.isProcessRunning(42), isTrue);
      expect(await checker.isProcessRunning(99), isFalse);
    });

    test('should report not running for non-positive pid on Windows path', () async {
      final checker = WindowsProcessLifetimeChecker(
        isWindows: () => true,
        openProcessForPid: (_) => 0,
      );

      expect(await checker.isProcessRunning(0), isFalse);
      expect(await checker.isProcessRunning(-1), isFalse);
    });
  });
}

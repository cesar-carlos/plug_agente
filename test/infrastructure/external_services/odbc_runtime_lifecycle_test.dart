import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_runtime_lifecycle.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('OdbcRuntimeLifecycle', () {
    late _MockOdbcService service;
    late OdbcRuntimeLifecycle lifecycle;

    setUp(() {
      service = _MockOdbcService();
      lifecycle = OdbcRuntimeLifecycle(service);
    });

    test('initializes once and reuses success state', () async {
      when(() => service.initialize()).thenAnswer((_) async => const Success(unit));

      final first = await lifecycle.ensureInitialized(operation: 'initialize_odbc');
      final second = await lifecycle.ensureInitialized(operation: 'initialize_odbc');

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      verify(() => service.initialize()).called(1);
      expect(lifecycle.isInitialized, isTrue);
    });

    test('invalidates cached init state after worker recovery', () async {
      when(() => service.initialize()).thenAnswer((_) async => const Success(unit));

      await lifecycle.ensureInitialized(operation: 'initialize_odbc');
      lifecycle.invalidateAfterWorkerRecovery();

      expect(lifecycle.isInitialized, isFalse);
      await lifecycle.ensureInitialized(operation: 'recover_odbc_after_worker_crash');
      verify(() => service.initialize()).called(2);
    });
  });
}

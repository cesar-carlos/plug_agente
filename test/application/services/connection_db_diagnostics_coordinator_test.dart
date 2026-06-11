import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/connection_db_diagnostics_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:result_dart/result_dart.dart';

class _MockTestDbConnection extends Mock implements TestDbConnection {}

class _MockCheckOdbcDriver extends Mock implements CheckOdbcDriver {}

void main() {
  late _MockTestDbConnection testDbConnection;
  late _MockCheckOdbcDriver checkOdbcDriver;
  late ConnectionDbDiagnosticsCoordinator coordinator;

  setUp(() {
    testDbConnection = _MockTestDbConnection();
    checkOdbcDriver = _MockCheckOdbcDriver();
    coordinator = ConnectionDbDiagnosticsCoordinator(
      testDbConnectionUseCase: testDbConnection,
      checkOdbcDriverUseCase: checkOdbcDriver,
    );
  });

  test('testDbConnection records success and updates db indicator', () async {
    when(() => testDbConnection('dsn=test')).thenAnswer((_) async => const Success(true));

    bool? dbIndicator;
    var notifyCount = 0;

    final result = await coordinator.testDbConnection(
      'dsn=test',
      recordGlobalError: true,
      setDbConnectionIndicator: (connected) => dbIndicator = connected,
      setGlobalError: (_) {},
      notifyStateChanged: () => notifyCount++,
    );

    expect(result.isSuccess(), isTrue);
    expect(dbIndicator, isTrue);
    expect(notifyCount, 1);
  });

  test('testDbConnection maps failure to global error when requested', () async {
    when(() => testDbConnection('dsn=test')).thenAnswer(
      (_) async => Failure(domain_failures.ConnectionFailure('db down')),
    );

    bool? dbIndicator;
    String? globalError;

    await coordinator.testDbConnection(
      'dsn=test',
      recordGlobalError: true,
      setDbConnectionIndicator: (connected) => dbIndicator = connected,
      setGlobalError: (message) => globalError = message,
      notifyStateChanged: () {},
    );

    expect(dbIndicator, isFalse);
    expect(globalError, 'db down');
  });

  test('checkOdbcDriver toggles checking flag and returns result', () async {
    when(() => checkOdbcDriver('SQL Server')).thenAnswer((_) async => const Success(true));

    final checkingStates = <bool>[];

    final result = await coordinator.checkOdbcDriver(
      'SQL Server',
      setCheckingDriver: checkingStates.add,
      setGlobalError: (_) {},
      notifyStateChanged: () {},
    );

    expect(result.isSuccess(), isTrue);
    expect(checkingStates, [true, false]);
  });
}

import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:result_dart/result_dart.dart';

/// Runs ODBC driver and database connectivity checks without Flutter widgets.
final class ConnectionDbDiagnosticsCoordinator {
  ConnectionDbDiagnosticsCoordinator({
    required TestDbConnection testDbConnectionUseCase,
    required CheckOdbcDriver checkOdbcDriverUseCase,
  }) : _testDbConnectionUseCase = testDbConnectionUseCase,
       _checkOdbcDriverUseCase = checkOdbcDriverUseCase;

  final TestDbConnection _testDbConnectionUseCase;
  final CheckOdbcDriver _checkOdbcDriverUseCase;

  Future<Result<bool>> testDbConnection(
    String connectionString, {
    required bool recordGlobalError,
    required void Function(bool connected) setDbConnectionIndicator,
    required void Function(String message) setGlobalError,
    required void Function() notifyStateChanged,
  }) async {
    final result = await _testDbConnectionUseCase(connectionString);

    result.fold(
      (bool isConnected) {
        setDbConnectionIndicator(isConnected);
        if (isConnected) {
          AppLogger.info('Database connection test successful');
        } else {
          AppLogger.warning('Database connection test failed');
        }
      },
      (Object failure) {
        setDbConnectionIndicator(false);
        if (recordGlobalError) {
          setGlobalError(failure.toDisplayMessage());
        }
        AppLogger.error(
          'Database connection test failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    notifyStateChanged();
    return result;
  }

  Future<Result<bool>> checkOdbcDriver(
    String driverName, {
    required void Function(bool checking) setCheckingDriver,
    required void Function(String message) setGlobalError,
    required void Function() notifyStateChanged,
  }) async {
    setCheckingDriver(true);
    setGlobalError('');
    notifyStateChanged();

    final result = await _checkOdbcDriverUseCase(driverName);

    result.fold(
      (isInstalled) {
        if (isInstalled) {
          AppLogger.info('ODBC driver "$driverName" is installed');
        } else {
          AppLogger.warning('ODBC driver "$driverName" is not installed');
        }
      },
      (failure) {
        setGlobalError(failure.toDisplayMessage());
        AppLogger.error(
          'Failed to check ODBC driver: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    setCheckingDriver(false);
    notifyStateChanged();
    return result;
  }
}

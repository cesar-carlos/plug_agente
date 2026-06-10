import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_context.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_driver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_timeout.dart';

/// Maps ODBC connection-time errors to typed [Failure] values.
class OdbcFailureMapperConnection {
  OdbcFailureMapperConnection._();

  static Failure map(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = OdbcFailureMapperContext.extractDetail(error);
    final sqlState = OdbcFailureMapperContext.extractSqlState(error);
    final baseContext = OdbcFailureMapperContext.buildBaseContext(error, operation, context);

    if (error is WorkerCrashedError) {
      return ConnectionFailure.withContext(
        message: 'ODBC worker was interrupted',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': true,
          'reason': OdbcContextConstants.odbcWorkerCrashedReason,
          'user_message': 'The ODBC connection was interrupted internally. Try running the operation again.',
        },
      );
    }

    if (OdbcFailureMapperDriver.isDriverMissing(sqlState, detail)) {
      return ConfigurationFailure.withContext(
        message: 'ODBC driver not found or not configured',
        cause: error,
        context: {
          ...baseContext,
          'database': true,
          'reason': OdbcContextConstants.odbcDriverNotFoundReason,
          'user_message':
              'The configured ODBC driver was not found on this computer. '
              'Review the driver and data source in settings.',
        },
      );
    }

    if (_isAuthenticationFailure(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Database authentication failed',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'reason': OdbcContextConstants.authenticationFailedReason,
          'user_message':
              'Could not authenticate to the database. '
              'Check username, password, and permissions.',
        },
      );
    }

    if (OdbcFailureMapperTimeout.isTimeout(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Connection timeout when connecting to database',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'timeout': true,
          'timeout_stage': 'connect',
          // Not directly retryable at RetryManager level; the gateway handles
          // its own reconnect logic for connection timeouts.
          'retryable': false,
          'reason': OdbcContextConstants.connectionTimeoutReason,
          'user_message':
              'The database connection took longer than expected. '
              'Confirm the server is accessible and try again.',
        },
      );
    }

    if (_isServerUnavailable(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Could not reach the database server',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': isRetryableConnection(sqlState),
          'reason': OdbcContextConstants.serverUnreachableReason,
          'user_message':
              'Could not connect to the database server. '
              'Check host, port, VPN, and network availability.',
        },
      );
    }

    return ConnectionFailure.withContext(
      message: 'Failed to connect to the database',
      cause: error,
      context: {
        ...baseContext,
        'connectionFailed': true,
        'retryable': isRetryableConnection(sqlState),
        'reason': OdbcContextConstants.databaseConnectionFailedReason,
        'user_message': 'Could not establish a connection to the database.',
      },
    );
  }

  /// SQLSTATE class 08 (connection exception) or equivalent message during execute.
  static bool isConnectionExceptionDuringExecute(String? sqlState, String detail) {
    if (sqlState != null && sqlState.startsWith('08')) {
      return true;
    }
    final normalized = detail.toLowerCase();
    return normalized.contains('communication link failure') ||
        normalized.contains('connection was terminated') ||
        normalized.contains('connection is no longer usable') ||
        normalized.contains('connection may have been terminated') ||
        (normalized.contains('tcp provider') && normalized.contains('error')) ||
        normalized.contains('broken pipe') ||
        normalized.contains('connection reset');
  }

  static bool isRetryableConnection(String? sqlState) {
    return sqlState != null && sqlState.startsWith('08');
  }

  static bool _isAuthenticationFailure(String? sqlState, String detail) {
    if (sqlState == '28000') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('login failed') ||
        normalized.contains('authentication failed') ||
        normalized.contains('invalid authorization') ||
        normalized.contains('access denied');
  }

  static bool _isServerUnavailable(String? sqlState, String detail) {
    if (sqlState != null && sqlState.startsWith('08')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('database server not found') ||
        normalized.contains('server does not exist') ||
        normalized.contains('could not connect') ||
        normalized.contains('network-related') ||
        normalized.contains('connection refused') ||
        normalized.contains('server unavailable') ||
        normalized.contains('unknown host');
  }
}

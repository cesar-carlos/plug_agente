import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/errors.dart';

class OdbcFailureMapper {
  OdbcFailureMapper._();

  static Failure mapConnectionError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final sqlState = _extractSqlState(error);
    final baseContext = _buildBaseContext(error, operation, context);

    if (_isDriverMissing(sqlState, detail)) {
      return ConfigurationFailure.withContext(
        message: 'Driver ODBC nao encontrado ou nao configurado',
        cause: error,
        context: {
          ...baseContext,
          'database': true,
          'reason': 'odbc_driver_not_found',
          'user_message':
              'O driver ODBC configurado nao foi encontrado neste computador. '
              'Revise o driver e a fonte de dados nas configuracoes.',
        },
      );
    }

    if (_isAuthenticationFailure(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Falha de autenticacao no banco de dados',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'reason': 'authentication_failed',
          'user_message':
              'Nao foi possivel autenticar no banco de dados. '
              'Verifique usuario, senha e permissoes.',
        },
      );
    }

    if (_isTimeout(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Tempo limite excedido ao conectar no banco de dados',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'timeout': true,
          'timeout_stage': 'sql',
          'reason': 'connection_timeout',
          'user_message':
              'A conexao com o banco demorou mais do que o esperado. '
              'Confirme se o servidor esta acessivel e tente novamente.',
        },
      );
    }

    if (_isServerUnavailable(sqlState, detail)) {
      return ConnectionFailure.withContext(
        message: 'Nao foi possivel alcancar o servidor de banco de dados',
        cause: error,
        context: {
          ...baseContext,
          'connectionFailed': true,
          'retryable': _isRetryableConnection(sqlState),
          'reason': 'server_unreachable',
          'user_message':
              'Nao foi possivel conectar ao servidor do banco. '
              'Verifique host, porta, VPN e disponibilidade da rede.',
        },
      );
    }

    return ConnectionFailure.withContext(
      message: 'Falha ao conectar no banco de dados',
      cause: error,
      context: {
        ...baseContext,
        'connectionFailed': true,
        'retryable': _isRetryableConnection(sqlState),
        'reason': 'database_connection_failed',
        'user_message':
            'Nao foi possivel estabelecer conexao com o banco de dados.',
      },
    );
  }

  static Failure mapQueryError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final sqlState = _extractSqlState(error);
    final baseContext = _buildBaseContext(error, operation, context);

    if (_isBufferTooSmall(detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'reason': 'buffer_too_small',
          'user_message':
              'O resultado da consulta excede o buffer atual. '
              'Ative o streaming ou aumente o buffer de resultados.',
        },
      );
    }

    if (_isTimeout(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: 'Tempo limite excedido durante a execucao da consulta',
        cause: error,
        context: {
          ...baseContext,
          'timeout': true,
          'timeout_stage': 'sql',
          'reason': 'query_timeout',
          'user_message':
              'A consulta demorou mais do que o permitido para concluir.',
        },
      );
    }

    if (_isTransientQueryFailure(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'retryable': true,
          'reason': 'transient_query_failure',
          'user_message':
              'O banco retornou uma falha transitoria ao executar a consulta. '
              'Tente novamente.',
        },
      );
    }

    if (_isPermissionDenied(sqlState, detail)) {
      return QueryExecutionFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'reason': 'sql_permission_denied',
          'user_message':
              'A consulta foi recusada por falta de permissao no banco de dados.',
        },
      );
    }

    if (_isSyntaxOrValidationError(sqlState, detail) ||
        error is ValidationError) {
      return ValidationFailure.withContext(
        message: detail,
        cause: error,
        context: {
          ...baseContext,
          'operation': 'sql_validation',
          'reason': 'sql_validation_failed',
          'user_message':
              'A consulta nao pode ser executada porque contem um erro de '
              'sintaxe ou referencia invalida.',
        },
      );
    }

    return QueryExecutionFailure.withContext(
      message: detail,
      cause: error,
      context: {
        ...baseContext,
        'reason': 'sql_execution_failed',
        'user_message':
            'O banco de dados retornou um erro ao executar a consulta.',
      },
    );
  }

  static Failure mapPoolError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = _extractDetail(error);
    final baseContext = _buildBaseContext(error, operation, context);
    final isExhausted = _isPoolExhausted(detail);

    return ConnectionFailure.withContext(
      message: isExhausted
          ? 'Pool de conexoes ODBC esgotado'
          : 'Falha ao obter conexao do pool ODBC',
      cause: error,
      context: {
        ...baseContext,
        'poolExhausted': isExhausted,
        'retryable': isExhausted,
        'reason': isExhausted ? 'pool_exhausted' : 'pool_error',
        'user_message': isExhausted
            ? 'O agente esta sem conexoes livres no momento. '
                  'Tente novamente em alguns instantes.'
            : 'Nao foi possivel obter uma conexao ODBC disponivel.',
      },
    );
  }

  static Failure mapStreamingError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool cancelledByUser = false,
  }) {
    final baseContext = _buildBaseContext(error, operation, context);

    if (cancelledByUser) {
      return QueryExecutionFailure.withContext(
        message: 'Streaming cancelado pelo usuario',
        cause: error,
        context: {
          ...baseContext,
          'reason': 'query_cancelled',
          'user_message': 'A consulta em streaming foi cancelada.',
        },
      );
    }

    return mapQueryError(
      error,
      operation: operation,
      context: {
        ...baseContext,
        'streaming': true,
      },
    );
  }

  static String _extractDetail(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  static String? _extractSqlState(Object error) {
    if (error is! OdbcError) {
      return null;
    }
    final sqlState = error.sqlState?.trim().toUpperCase();
    return (sqlState == null || sqlState.isEmpty) ? null : sqlState;
  }

  static Map<String, dynamic> _buildBaseContext(
    Object error,
    String? operation,
    Map<String, dynamic> context,
  ) {
    final sqlState = _extractSqlState(error);
    final nativeCode = error is OdbcError ? error.nativeCode : null;

    return {
      ...?(operation != null ? {'operation': operation} : null),
      'odbc_error_type': error.runtimeType.toString(),
      'odbc_message': _extractDetail(error),
      ...?(sqlState != null ? {'odbc_sql_state': sqlState} : null),
      ...?(nativeCode != null ? {'odbc_native_code': nativeCode} : null),
      ...context,
    };
  }

  static bool _isDriverMissing(String? sqlState, String detail) {
    // 08xxx = connection/server errors (e.g. 08001 "Database server not found")
    if (sqlState != null && sqlState.startsWith('08')) {
      return false;
    }

    if (sqlState == 'IM002' || sqlState == 'IM003') {
      return true;
    }

    final normalized = detail.toLowerCase();
    // "Database server not found" = server unreachable, not driver missing
    if (normalized.contains('database server not found')) {
      return false;
    }

    return normalized.contains('data source name not found') ||
        normalized.contains('no default driver specified') ||
        (normalized.contains('driver') && normalized.contains('not found')) ||
        normalized.contains("can't open lib") ||
        normalized.contains('library not found');
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

  static bool _isTimeout(String? sqlState, String detail) {
    if (sqlState == 'HYT00' || sqlState == 'HYT01') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('hyt00') ||
        normalized.contains('hyt01');
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

  static bool _isSyntaxOrValidationError(String? sqlState, String detail) {
    if (sqlState != null &&
        (sqlState.startsWith('42') ||
            sqlState.startsWith('22') ||
            sqlState == '07001' ||
            sqlState == '07002' ||
            sqlState == '07006' ||
            sqlState == '07009' ||
            sqlState == '21S01' ||
            sqlState == '21S02')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('syntax') ||
        normalized.contains('incorrect syntax') ||
        normalized.contains('invalid column') ||
        normalized.contains('invalid object') ||
        normalized.contains('does not exist') ||
        normalized.contains('undeclared');
  }

  static bool _isPermissionDenied(String? sqlState, String detail) {
    if (sqlState == '42501') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('permission denied') ||
        normalized.contains('not authorized') ||
        normalized.contains('insufficient privilege') ||
        normalized.contains('permission was denied');
  }

  static bool _isTransientQueryFailure(String? sqlState, String detail) {
    if (sqlState != null &&
        (sqlState.startsWith('40') ||
            sqlState == 'HY008' ||
            sqlState == 'HY117')) {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('deadlock') ||
        normalized.contains('serialization failure') ||
        normalized.contains('lock request time out');
  }

  static bool _isPoolExhausted(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains('pool exhausted') ||
        normalized.contains('no connections available') ||
        normalized.contains('all pooled connections are busy');
  }

  static bool _isBufferTooSmall(String detail) {
    return detail.toLowerCase().contains('buffer too small');
  }

  static bool _isRetryableConnection(String? sqlState) {
    return sqlState != null && sqlState.startsWith('08');
  }
}

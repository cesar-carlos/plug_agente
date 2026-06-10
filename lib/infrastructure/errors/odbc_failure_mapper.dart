import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_connection.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_pool.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_query.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_streaming.dart';

/// Facade for ODBC error-to-[Failure] mapping. Category-specific logic lives in
/// [OdbcFailureMapperConnection], [OdbcFailureMapperQuery], [OdbcFailureMapperPool],
/// and related modules under infrastructure/external_services/.
class OdbcFailureMapper {
  OdbcFailureMapper._();

  static Failure mapConnectionError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    return OdbcFailureMapperConnection.map(
      error,
      operation: operation,
      context: context,
    );
  }

  static Failure mapQueryError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    return OdbcFailureMapperQuery.map(
      error,
      operation: operation,
      context: context,
    );
  }

  static Failure mapPoolError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    return OdbcFailureMapperPool.map(
      error,
      operation: operation,
      context: context,
    );
  }

  static Failure mapStreamingError(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool cancelledByUser = false,
  }) {
    return OdbcFailureMapperStreaming.map(
      error,
      operation: operation,
      context: context,
      cancelledByUser: cancelledByUser,
    );
  }
}

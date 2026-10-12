import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' hide Failure;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_response_factory.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:result_dart/result_dart.dart';

/// Read-only, bounded materialization. No pool, cached rows, DB stream or retry.
class OdbcVerifiedQuery {
  const OdbcVerifiedQuery(this.sessions);
  final OdbcSourceDiscovery sessions;
  Future<Result<QueryResponse>> execute(QueryRequest request, Config config, String database, Duration timeout) async {
    final expected = request.expectedSource!;
    if (request.expectMultipleResults || !SqlValidator.isReadOnlyQuery(request.query)) {
      return Failure(ValidationFailure('Verified query requires a single read-only result.'));
    }
    return sessions.withConnection(
      config,
      database,
      (id, remaining) async {
        final started = DateTime.now();
        final proof = await OdbcSourceDiscovery.inspectConnection(sessions.service, id, config, database);
        expected.verify(proof);
        // Firebird pagination is compiled by MCP; never route it through T-SQL.
        if (proof.dialect == 'firebird' && request.pagination != null) {
          throw ValidationFailure('Firebird verified queries require explicit trained pagination SQL.');
        }
        final db = DatabaseConfig(
          driverName: '',
          username: '',
          password: '',
          database: database,
          server: '',
          port: 0,
          databaseType: switch (proof.dialect) {
            'postgres' => DatabaseType.postgresql,
            'sybase' => DatabaseType.sybaseAnywhere,
            _ => DatabaseType.sqlServer,
          },
        );
        final invalid = OdbcGatewayQueryPreparation.validatePaginationForDatabase(request, db.databaseType);
        if (invalid != null) throw invalid;
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(request, db);
        remaining();
        final executed = await sessions.service.executeQueryNamed(id, prepared.sql, prepared.parameters ?? const {});
        if (executed.isError()) throw OdbcFailureMapper.mapQueryError(executed.exceptionOrNull()!, operation: 'query');
        final result = executed.getOrThrow();
        if (result.additionalResults.isNotEmpty ||
            result.refCursorResults.isNotEmpty ||
            result.rows.length != result.rowCount) {
          throw ValidationFailure('Incomplete or multiple verified query results are refused.');
        }
        remaining();
        expected.verify(await OdbcSourceDiscovery.inspectConnection(sessions.service, id, config, database));
        remaining();
        return OdbcQueryResponseFactory.fromSingleResult(request, result, startedAt: started);
      },
      timeout: timeout,
      maxResultBufferBytes: 16 * 1024 * 1024,
    );
  }
}

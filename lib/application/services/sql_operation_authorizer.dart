import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/services/sql_operation_statement_guard.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:result_dart/result_dart.dart';

class SqlOperationAuthorizer implements ISqlOperationAuthorizer {
  SqlOperationAuthorizer(this._configs, this._tokens)
    : _authorize = AuthorizeSqlOperation(SqlOperationClassifier(), _tokens);
  final IQueryConfigSource _configs;
  final ClientTokenValidationService _tokens;
  // No decision cache on the operation path; validate live policy before each step and commit.
  final AuthorizeSqlOperation _authorize;
  @override
  Future<Result<SqlOperationTarget>> authorize(
    SqlOperationReference ref,
    String token,
    String agentId,
    List<SqlOperationStep> steps,
  ) async {
    try {
      final policy = (await _tokens.validate(token)).getOrThrow();
      if (RegExp(r'[;{}\r\n\x00]').hasMatch(ref.database) ||
          policy.isRevoked ||
          policy.agentId != agentId ||
          policy.payloadDatabaseConstraint == null ||
          policy.payloadDatabaseConstraint != ref.database.trim().toLowerCase()) {
        _deny();
      }
      final config = (await _configs.resolveActiveConfig()).getOrThrow();
      if (config.agentId != agentId) _deny();
      final url = Uri.parse(config.serverUrl);
      final origin = url.origin;
      final physical = sha256
          .convert(
            utf8.encode(
              jsonEncode(
                ref.expectedSource == null
                    ? [origin, agentId, ref.database]
                    : [origin, ref.expectedSource!.identityHash],
              ),
            ),
          )
          .toString();
      if (physical != ref.sourcePhysicalId) _deny();
      for (final step in steps) {
        const SqlOperationStatementGuard().validate(step);
        (await _authorize(
          token: token,
          sql: step.sql,
          requestDatabase: ref.database,
          method: 'sql.operation.execute',
        )).getOrThrow();
      }
      final scope = buildIdempotencyFingerprintForEnvelope({
        'hubOrigin': origin,
        'agentId': agentId,
        'sourcePhysicalId': physical,
        if (ref.expectedSource != null) 'expectedSource': ref.expectedSource!.toJson(),
        'tokenHash': sha256.convert(utf8.encode(token)).toString(),
      });
      final revision = buildIdempotencyFingerprintForEnvelope({
        'policy': policy.toJson(),
        'payload': policy.payload,
        'credentialExpiresAt': policy.credentialExpiresAt?.toUtc().toIso8601String(),
        'configId': config.id,
        'driver': config.odbcDriverName,
        'host': config.host,
        'port': config.port,
        'database': ref.database,
        'connectionHash': sha256.convert(utf8.encode(config.connectionString)).toString(),
        'username': config.username,
        'credentialHash': sha256.convert(utf8.encode(config.password ?? '')).toString(),
      });
      return Success(
        SqlOperationTarget(
          config: config,
          database: ref.database,
          scopeHash: scope,
          authorizationHash: revision,
          expectedSource: ref.expectedSource,
        ),
      );
    } on Exception catch (error) {
      return Failure(error);
    }
  }

  static Never _deny() => throw SqlOperationFailure(
    code: 'SQL_OPERATION_AUTHORIZATION_DENIED',
    message: 'Live agent, database, physical source and token policy must match.',
  );
}

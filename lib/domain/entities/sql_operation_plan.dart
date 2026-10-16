import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/expected_structure.dart';

enum SqlOperationEffect { select, insert, update, delete }

enum SqlScalarType { string, decimal, date, uuid, integer, boolean, nullValue }

class SqlScalar {
  const SqlScalar(this.type, this.value);
  final SqlScalarType type;
  final Object? value;
}

sealed class SqlOperationBinding {
  const SqlOperationBinding();
}

class SqlOperationValue extends SqlOperationBinding {
  const SqlOperationValue(this.scalar);
  final SqlScalar scalar;
}

class SqlOperationOutput extends SqlOperationBinding {
  const SqlOperationOutput(this.stepId, this.output);
  final String stepId;
  final String output;
}

class SqlRowBounds {
  const SqlRowBounds(this.min, this.max);
  final int min;
  final int max;
  bool contains(int n) => n >= min && n <= max;
}

class SqlOperationStep {
  const SqlOperationStep({
    required this.id,
    required this.effect,
    required this.sql,
    required this.params,
    required this.outputs,
    this.affectedRows,
    this.expectedRows,
  });
  final String id;
  final SqlOperationEffect effect;
  final String sql;
  final Map<String, SqlOperationBinding> params;
  final Map<String, SqlScalarType> outputs;
  final SqlRowBounds? affectedRows;
  final SqlRowBounds? expectedRows;
}

class SqlOperationReference {
  const SqlOperationReference({
    required this.operationId,
    required this.fingerprint,
    required this.database,
    required this.sourcePhysicalId,
    this.expectedSource,
  });
  final String operationId;
  final String fingerprint;
  final String database;
  final String sourcePhysicalId;
  final ExpectedSource? expectedSource;
}

class SqlOperationPlan extends SqlOperationReference {
  const SqlOperationPlan({
    required super.operationId,
    required super.fingerprint,
    required super.database,
    required super.sourcePhysicalId,
    required this.steps,
    required this.maxAffectedRows,
    required this.timeout,
    required this.contentHash,
    this.expectedStructure,
    super.expectedSource,
  });
  final ExpectedStructure? expectedStructure;
  int nativeStatementCount(String dialect) =>
      1 +
      steps.fold<int>(
        0,
        (count, step) =>
            count + (step.effect != SqlOperationEffect.select && {'mssql', 'sybase'}.contains(dialect) ? 2 : 1),
      ) +
      (expectedStructure == null ? 0 : expectedStructure!.verificationStatementCount + 1);
  final List<SqlOperationStep> steps;
  final int maxAffectedRows;
  final Duration timeout;

  /// Hash calculated by the agent from all execution fields, independently of caller fingerprint.
  final String contentHash;
}

class SqlOperationTarget {
  const SqlOperationTarget({
    required this.config,
    required this.database,
    required this.scopeHash,
    required this.authorizationHash,
    this.expectedSource,
  });
  final Config config;
  final String database;
  final String scopeHash;
  final String authorizationHash;
  final ExpectedSource? expectedSource;
}

class SqlOperationStepResult {
  const SqlOperationStepResult({required this.rows, required this.directlyAffectedRows});
  final List<Map<String, Object?>> rows;

  /// Null is indeterminate, never zero by inference.
  final int? directlyAffectedRows;
}

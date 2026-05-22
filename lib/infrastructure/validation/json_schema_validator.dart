import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

/// Thin wrapper around [TransportSchemaLoader] that runs JSON Schema
/// validation by short id (file name).
///
/// This is the runtime arm of the schema fonte-de-verdade: while the procedural
/// validators in `RpcRequestSchemaValidator` and `RpcContractValidator`
/// continue to enforce protocol semantics, this validator is the canonical
/// enforcer of the wire shape declared in `docs/communication/schemas/`.
///
/// Use it in:
///   - boot-time contract tests that probe fixtures against schemas;
///   - selective production validation where the schema covers more rules
///     than the procedural code (e.g. `agent.getProfile` `additionalProperties`).
class JsonSchemaContractValidator {
  JsonSchemaContractValidator({
    required TransportSchemaLoader loader,
    ISchemaValidationMetricsCollector? metrics,
  }) : _loader = loader,
       _metrics = metrics;

  final TransportSchemaLoader _loader;
  final ISchemaValidationMetricsCollector? _metrics;

  /// Validates [payload] against the schema with [schemaId]. Returns
  /// `Success(unit)` when the schema is missing (so the caller may fall back
  /// to procedural validation) or when validation passes; otherwise returns
  /// a `ValidationFailure` carrying the JSON pointer paths of failing nodes.
  Result<void> validate({
    required String schemaId,
    required Object? payload,
    String direction = 'unknown',
  }) {
    final schema = _loader.get(schemaId);
    if (schema == null) {
      // Schema not loaded: skip JSON Schema validation and fall through to
      // procedural validation. Log at fine level so production traces can
      // show when schema coverage is incomplete.
      assert(() {
        // ignore: avoid_print
        print('[JsonSchemaContractValidator] schema "$schemaId" not loaded — skipping');
        return true;
      }(), 'schema "$schemaId" not loaded');
      return const Success(unit);
    }
    final stopwatch = Stopwatch()..start();
    final result = schema.validate(payload);
    if (result.isValid) {
      stopwatch.stop();
      _metrics?.recordSchemaValidation(
        direction: direction,
        schemaId: schemaId,
        success: true,
        elapsed: stopwatch.elapsed,
      );
      return const Success(unit);
    }
    stopwatch.stop();
    _metrics?.recordSchemaValidation(
      direction: direction,
      schemaId: schemaId,
      success: false,
      elapsed: stopwatch.elapsed,
    );
    final errors = result.errors
        .map((e) => '${e.instancePath.isEmpty ? '/' : e.instancePath}: ${e.message}')
        .join('; ');
    return Failure(
      domain.ValidationFailure.withContext(
        message: 'Schema validation failed for $schemaId: $errors',
        context: {
          'schema_id': schemaId,
          'error_count': result.errors.length,
          'first_error_path': result.errors.isEmpty ? '/' : result.errors.first.instancePath,
        },
      ),
    );
  }

  /// Whether the schema with [schemaId] is loaded and usable. Lets callers
  /// decide upfront whether to skip JSON Schema validation entirely.
  bool isLoaded(String schemaId) => _loader.get(schemaId) != null;

  void recordSkippedLargePayload({required String direction}) {
    _metrics?.recordSchemaValidationSkippedLargePayload(
      direction: direction,
    );
  }
}

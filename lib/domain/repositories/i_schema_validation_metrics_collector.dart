/// Observability surface for runtime JSON Schema validation.
abstract class ISchemaValidationMetricsCollector {
  void recordSchemaValidation({
    required String direction,
    required String schemaId,
    required bool success,
    required Duration elapsed,
  });

  void recordSchemaValidationSkippedLargePayload({
    required String direction,
  });
}

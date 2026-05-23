import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';

abstract class IProtocolMetricsCollector {
  /// Fires after each recorded metric (lightweight UI refresh signal).
  Stream<void> get updates;

  ProtocolMetricsSummary getSummary({Duration? period});
}

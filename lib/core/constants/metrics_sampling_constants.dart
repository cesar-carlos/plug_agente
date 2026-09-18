import 'package:plug_agente/core/constants/connection_constants_env.dart';

/// Bounds for the in-memory samples used to calculate latency percentiles.
abstract final class MetricsSamplingConstants {
  static const int defaultLatencySampleCapacity = 256;
  static const int minLatencySampleCapacity = 64;
  static const int maxLatencySampleCapacity = 1000;
  static const Duration percentileSnapshotCacheTtl = Duration(seconds: 1);

  static int get latencySampleCapacity {
    final configured = ConnectionConstantsEnv.positiveInt(
      'METRICS_LATENCY_SAMPLE_CAP',
    );
    return (configured ?? defaultLatencySampleCapacity).clamp(
      minLatencySampleCapacity,
      maxLatencySampleCapacity,
    );
  }
}

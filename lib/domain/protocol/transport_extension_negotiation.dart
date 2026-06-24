/// Helpers for performance-related transport extensions negotiated with the hub.
///
/// See `plug_server/docs/adrs/` (0009, 0010, 0011) and
/// `plug_server/docs/plug_agente/03_performance_roadmap.md`.
abstract final class TransportExtensionNegotiation {
  static const String clientRequestIdEcho = 'clientRequestIdEcho';
  static const String agentPhaseTimings = 'agentPhaseTimings';
  static const String healthPiggyback = 'healthPiggyback';

  static const String clientRequestIdEchoVersion = 'v1';
  static const String agentPhaseTimingsVersion = 'v1';

  static const int defaultHealthPiggybackIntervalRequests = 50;
  static const int defaultHealthPiggybackFreshnessThresholdMs = 5000;

  static bool isClientRequestIdEchoNegotiated(Map<String, dynamic> extensions) {
    return extensions[clientRequestIdEcho] == clientRequestIdEchoVersion;
  }

  static bool isAgentPhaseTimingsNegotiated(Map<String, dynamic> extensions) {
    return extensions[agentPhaseTimings] == agentPhaseTimingsVersion;
  }

  static HealthPiggybackNegotiation? parseHealthPiggyback(Map<String, dynamic> extensions) {
    final raw = extensions[healthPiggyback];
    if (raw is! Map) {
      return null;
    }
    final interval = _positiveInt(raw['intervalRequests']) ?? defaultHealthPiggybackIntervalRequests;
    final freshnessMs =
        _positiveInt(raw['freshnessThresholdMs']) ?? defaultHealthPiggybackFreshnessThresholdMs;
    return HealthPiggybackNegotiation(
      intervalRequests: interval,
      freshnessThresholdMs: freshnessMs,
    );
  }

  static Map<String, dynamic> defaultHealthPiggybackAdvertisement() {
    return <String, dynamic>{
      'intervalRequests': defaultHealthPiggybackIntervalRequests,
      'freshnessThresholdMs': defaultHealthPiggybackFreshnessThresholdMs,
    };
  }

  static int? _positiveInt(Object? value) {
    if (value is int && value > 0) {
      return value;
    }
    if (value is num && value > 0) {
      return value.toInt();
    }
    return null;
  }
}

final class HealthPiggybackNegotiation {
  const HealthPiggybackNegotiation({
    required this.intervalRequests,
    required this.freshnessThresholdMs,
  });

  final int intervalRequests;
  final int freshnessThresholdMs;
}

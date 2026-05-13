abstract class IDirectConnectionLimiterDiagnostics {
  int get activeCount;

  int get maxConcurrent;

  int get openedTotal;

  int get closedTotal;

  bool get isSaturated;
}

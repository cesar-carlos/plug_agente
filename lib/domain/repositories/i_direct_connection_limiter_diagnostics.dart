abstract class IDirectConnectionLimiterDiagnostics {
  int get activeCount;

  int get maxConcurrent;

  int get openedTotal;

  int get closedTotal;

  bool get isSaturated;

  /// Per-operation-class active counts, caps and saturation flags for health.
  Map<String, Object?> getOperationClassDiagnostics();
}

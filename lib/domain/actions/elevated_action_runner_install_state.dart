/// Observed install state for the Windows elevated action runner.
enum ElevatedActionRunnerInstallState {
  unsupportedPlatform,
  helperExecutableMissing,
  scheduledTaskMissing,
  markerMissing,
  /// Task is registered but `/TR` points to a different helper executable
  /// than the current installation. Reinstall is required so that updates
  /// can take effect even if the previous marker still indicates `ready`.
  helperPathChanged,
  ready,
}

class ElevatedActionRunnerInstallStatus {
  const ElevatedActionRunnerInstallStatus({
    required this.state,
    this.helperExecutablePath,
  });

  final ElevatedActionRunnerInstallState state;
  final String? helperExecutablePath;

  bool get isReady => state == ElevatedActionRunnerInstallState.ready;
}

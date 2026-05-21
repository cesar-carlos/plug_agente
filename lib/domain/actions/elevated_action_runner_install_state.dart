/// Observed install state for the Windows elevated action runner.
enum ElevatedActionRunnerInstallState {
  unsupportedPlatform,
  helperExecutableMissing,
  scheduledTaskMissing,
  markerMissing,
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

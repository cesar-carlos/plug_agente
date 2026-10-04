import 'package:result_dart/result_dart.dart';

/// Local updater protocol. It does not extend the hub RPC contract.
enum UpdaterPhase {
  idle,
  downloaded,
  validating,
  authorizationRequired,
  deferred,
  preparing,
  waitingForExit,
  snapshotting,
  installing,
  verifying,
  completed,
  rollingBack,
  restoringUserData,
  rolledBack,
  recoveryRequired,
}

class UpdaterStatus {
  const UpdaterStatus({
    required this.phase,
    this.operationId,
    this.version,
    this.reason,
    this.missingCapabilities = const [],
    this.rebootPending = false,
  });

  final UpdaterPhase phase;
  final String? operationId;
  final String? version;
  final String? reason;
  final List<String> missingCapabilities;
  final bool rebootPending;

  bool get terminal => switch (phase) {
    UpdaterPhase.completed || UpdaterPhase.rolledBack => true,
    _ => false,
  };

  /// Attention does not prove that an installer, lock or native resource ended.
  bool get requiresRecovery => phase == UpdaterPhase.recoveryRequired;
}

class UpdaterCapabilities {
  const UpdaterCapabilities({
    required this.authorized,
    required this.applicationReady,
    required this.channel,
    required this.approved,
  });

  final bool authorized;
  final bool applicationReady;
  final String channel;
  final List<String> approved;

  bool get canApplyAutomatically => authorized && applicationReady;
}

/// Dispatch is acknowledged separately from installation and health success.
class UpdaterStartConfirmation {
  const UpdaterStartConfirmation({required this.status, required this.healthNonce});

  final UpdaterStatus status;
  final String healthNonce;
}

abstract interface class IPrivilegedUpdater {
  Future<Result<UpdaterCapabilities>> capabilities();
  Future<Result<UpdaterStatus>> status();
  Future<Result<UpdaterStatus>> prepare({required Map<String, Object?> manifest, required String installerPath});
  Future<Result<UpdaterStatus>> cancel(String operationId);
  Future<Result<UpdaterStartConfirmation>> start({
    required String operationId,
    required int appPid,
    required String dataDirectory,
    required String encryptedSecretsSnapshot,
  });
  Future<Result<void>> confirmHealth({required String operationId, required String version, required String nonce});
}

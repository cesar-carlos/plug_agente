/// Installer handshake that asks the interactive user session to register HKCU auto-start.
abstract interface class IInstallerAutostartRequestStore {
  Future<bool> hasPendingRequest();

  Future<void> clearPendingRequest();
}

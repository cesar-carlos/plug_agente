import 'package:result_dart/result_dart.dart';

/// Reads and restores flutter_secure_storage entries eligible for local backup.
abstract interface class IBackupSecureStorageSecretsPort {
  bool get isAvailable;

  Future<Result<Map<String, String>>> readBackupEligibleEntries();

  Future<Result<void>> restoreBackupEligibleEntries(Map<String, String> entries);
}

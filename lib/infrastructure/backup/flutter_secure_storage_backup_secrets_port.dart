import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/backup/backup_secure_storage_secrets_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_backup_secure_storage_secrets_port.dart';
import 'package:result_dart/result_dart.dart';

class FlutterSecureStorageBackupSecretsPort implements IBackupSecureStorageSecretsPort {
  FlutterSecureStorageBackupSecretsPort({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  bool get isAvailable => true;

  @override
  Future<Result<Map<String, String>>> readBackupEligibleEntries() async {
    try {
      final allEntries = await _secureStorage.readAll();
      final filtered = <String, String>{};
      for (final entry in allEntries.entries) {
        if (!_isEligibleKey(entry.key)) {
          continue;
        }
        final value = entry.value.trim();
        if (value.isEmpty) {
          continue;
        }
        filtered[entry.key] = value;
      }
      return Success(filtered);
    } on Exception catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Could not read secure storage for backup export',
          cause: error,
          context: const {'operation': 'readBackupEligibleEntries'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> restoreBackupEligibleEntries(Map<String, String> entries) async {
    try {
      for (final entry in entries.entries) {
        if (!_isEligibleKey(entry.key)) {
          continue;
        }
        final value = entry.value.trim();
        if (value.isEmpty) {
          continue;
        }
        await _secureStorage.write(key: entry.key, value: value);
      }
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Could not restore secure storage secrets from backup',
          cause: error,
          context: const {'operation': 'restoreBackupEligibleEntries'},
        ),
      );
    }
  }

  static bool _isEligibleKey(String key) {
    for (final prefix in BackupSecureStorageSecretsConstants.eligibleKeyPrefixes) {
      if (key.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }
}

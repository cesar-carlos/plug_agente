import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/backup/backup_secure_storage_secrets_constants.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_backup_secure_storage_secrets_port.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/backup/backup_secure_storage_secrets_cipher.dart';
import 'package:plug_agente/infrastructure/backup/backup_sqlite_reader.dart';
import 'package:plug_agente/infrastructure/backup/backup_zip_encoder.dart';
import 'package:plug_agente/infrastructure/backup/connected_agents_response_parser.dart';
import 'package:plug_agente/infrastructure/backup/flutter_secure_storage_backup_secrets_port.dart';
import 'package:plug_agente/infrastructure/backup/restore_failure_diagnostics.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

const int _backupExportIsolateMinBytes = 512 * 1024;

/// Maximum allowed ZIP archive size on disk (500 MB).
const int _backupMaxZipBytes = 500 * 1024 * 1024;

/// Maximum allowed total uncompressed size across all entries (2 GB).
const int _backupMaxUncompressedBytes = 2 * 1024 * 1024 * 1024;

const int _backupManifestFormatVersion = 1;
const String _manifestFileName = 'manifest.json';
const String _dbFileName = 'agent_config.db';
const String _settingsFileName = 'settings.json';
const String _secureStorageSecretsFileName = BackupSecureStorageSecretsConstants.zipEntryFileName;

const Set<String> _allowedZipBasenames = {
  _manifestFileName,
  _dbFileName,
  _settingsFileName,
  _secureStorageSecretsFileName,
};

Map<String, dynamic> _backupErr(String code) => <String, dynamic>{
  LocalBackupErrorCodes.contextKey: code,
};

/// Exports and restores Drift DB + global `settings.json` under [GlobalStorageContext].
class LocalAppDataBackupService implements ILocalAppDataBackupService {
  LocalAppDataBackupService({
    required AppDatabase database,
    required GlobalStorageContext storageContext,
    required IAppSettingsStore settingsStore,
    required IAuthClient authClient,
    required IConnectedAgentsGateway connectedAgentsGateway,
    IBackupSecureStorageSecretsPort? secureStorageSecretsPort,
  }) : _database = database,
       _storageContext = storageContext,
       _settingsStore = settingsStore,
       _authClient = authClient,
       _connectedAgentsGateway = connectedAgentsGateway,
       _secureStorageSecretsPort = secureStorageSecretsPort ?? FlutterSecureStorageBackupSecretsPort();

  final AppDatabase _database;
  final GlobalStorageContext _storageContext;
  final IAppSettingsStore _settingsStore;
  final IAuthClient _authClient;
  final IConnectedAgentsGateway _connectedAgentsGateway;
  final IBackupSecureStorageSecretsPort _secureStorageSecretsPort;

  @override
  int get liveAgentConfigSchemaVersion => _database.schemaVersion;

  @override
  Future<Result<void>> exportBackupZip(
    String destinationZipPath, {
    bool includeSecureStorageSecrets = false,
  }) async {
    final out = File(destinationZipPath);
    try {
      developer.log(
        'operation=exportBackupZip phase=start includeSecureStorageSecrets=$includeSecureStorageSecrets',
        name: 'local_app_data_backup',
      );

      final installationId = await _ensureInstallationId();
      var secretsIncluded = false;
      var secretsEntryCount = 0;
      Uint8List? secureStorageSecretsBytes;

      if (includeSecureStorageSecrets) {
        if (!_secureStorageSecretsPort.isAvailable) {
          return Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Secure storage is not available for backup export',
              context: {
                'operation': 'exportBackupZip',
                ..._backupErr(LocalBackupErrorCodes.exportSecretsUnavailable),
              },
            ),
          );
        }

        final entriesResult = await _secureStorageSecretsPort.readBackupEligibleEntries();
        if (entriesResult.isError()) {
          final failure = entriesResult.exceptionOrNull()!;
          return Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Could not read secure storage secrets for backup export',
              cause: failure is domain.Failure ? failure.cause : failure,
              context: {
                'operation': 'exportBackupZip',
                ..._backupErr(LocalBackupErrorCodes.exportSecretsUnavailable),
              },
            ),
          );
        }

        final entries = entriesResult.getOrThrow();
        if (entries.isNotEmpty) {
          try {
            secureStorageSecretsBytes = await BackupSecureStorageSecretsCipher.encryptEntries(entries);
            secretsIncluded = true;
            secretsEntryCount = entries.length;
          } on Object catch (error, stackTrace) {
            developer.log(
              'operation=exportBackupZip outcome=failure backupError=${LocalBackupErrorCodes.exportSecretsEncrypt}',
              name: 'local_app_data_backup',
              error: error,
              stackTrace: stackTrace,
            );
            return Failure(
              domain.ConfigurationFailure.withContext(
                message: 'Failed to encrypt secure storage secrets for backup export',
                cause: error,
                context: {
                  'operation': 'exportBackupZip',
                  ..._backupErr(LocalBackupErrorCodes.exportSecretsEncrypt),
                },
              ),
            );
          }
        }
      }

      final manifest = <String, dynamic>{
        'formatVersion': _backupManifestFormatVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': AppConstants.appVersion,
        'platform': Platform.operatingSystem,
        'installationId': installationId,
        'odbcSecretsIncluded': secretsIncluded,
        'secureStorageSecretsIncluded': secretsIncluded,
        if (secretsIncluded) ...<String, dynamic>{
          'secureStorageSecretsBlobVersion': BackupSecureStorageSecretsConstants.blobFormatVersion,
          'secureStorageSecretsEntryCount': secretsEntryCount,
        },
      };

      final dbFile = File(_storageContext.databaseFilePath);
      final settingsFile = File(_storageContext.settingsFilePath);

      if (!dbFile.existsSync()) {
        developer.log(
          'operation=exportBackupZip outcome=failure backupError=${LocalBackupErrorCodes.exportDbNotFound}',
          name: 'local_app_data_backup',
        );
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Local database file was not found',
            context: {
              'operation': 'exportBackupZip',
              ..._backupErr(LocalBackupErrorCodes.exportDbNotFound),
            },
          ),
        );
      }

      final dbBytes = await _readDbBytesWithCheckpointOrVacuumFallback(dbFile);

      Uint8List? settingsBytes;
      if (settingsFile.existsSync()) {
        settingsBytes = Uint8List.fromList(await settingsFile.readAsBytes());
      }

      final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
      final payloadBytes =
          manifestBytes.length +
          dbBytes.length +
          (settingsBytes?.length ?? 0) +
          (secureStorageSecretsBytes?.length ?? 0);
      final zipBytes = await _encodeZipPayload(
        manifestBytes: manifestBytes,
        dbBytes: dbBytes,
        settingsBytes: settingsBytes,
        secureStorageSecretsBytes: secureStorageSecretsBytes,
        payloadBytes: payloadBytes,
      );
      if (zipBytes == null) {
        developer.log(
          'operation=exportBackupZip outcome=failure backupError=${LocalBackupErrorCodes.exportZip}',
          name: 'local_app_data_backup',
        );
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to build backup archive',
            context: {
              'operation': 'exportBackupZip',
              ..._backupErr(LocalBackupErrorCodes.exportZip),
            },
          ),
        );
      }

      final parent = out.parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }
      // Write to a temporary file first, then rename atomically so a crash
      // mid-write never leaves a partial archive at the destination path.
      final tmp = File('${out.path}.tmp');
      await tmp.writeAsBytes(zipBytes, flush: true);
      if (out.existsSync()) {
        await out.delete();
      }
      await tmp.rename(out.path);
      developer.log(
        'operation=exportBackupZip outcome=success bytes=$payloadBytes zipBytes=${zipBytes.length} secretsIncluded=$secretsIncluded',
        name: 'local_app_data_backup',
      );
      return const Success(unit);
    } on FileSystemException catch (e, st) {
      developer.log(
        'operation=exportBackupZip outcome=failure backupError=${LocalBackupErrorCodes.exportWrite}',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Could not write backup file',
          cause: e,
          context: {
            'operation': 'exportBackupZip',
            'path': destinationZipPath,
            ..._backupErr(LocalBackupErrorCodes.exportWrite),
          },
        ),
      );
    } on Exception catch (e, st) {
      developer.log(
        'operation=exportBackupZip outcome=failure backupError=${LocalBackupErrorCodes.exportGeneric}',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return Failure(
        domain.DatabaseFailure.withContext(
          message: 'Unexpected error while exporting backup',
          cause: e,
          context: {
            'operation': 'exportBackupZip',
            ..._backupErr(LocalBackupErrorCodes.exportGeneric),
          },
        ),
      );
    }
  }

  @override
  Future<Result<RestoreStagingSnapshot>> stageRestoreFromZip(String zipPath) async {
    Directory? staging;
    try {
      final zipFile = File(zipPath);
      final zipStat = zipFile.statSync();
      if (zipStat.size > _backupMaxZipBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Backup archive is too large',
            context: {
              'size_bytes': zipStat.size,
              'max_bytes': _backupMaxZipBytes,
              ..._backupErr(LocalBackupErrorCodes.invalidEntry),
            },
          ),
        );
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Guard against zip-bomb: reject if total uncompressed size exceeds cap.
      final totalUncompressed = archive.files.fold<int>(
        0,
        (sum, f) => sum + (f.isFile ? (f.size) : 0),
      );
      if (totalUncompressed > _backupMaxUncompressedBytes) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Backup archive uncompressed size exceeds limit',
            context: {
              'uncompressed_bytes': totalUncompressed,
              'max_bytes': _backupMaxUncompressedBytes,
              ..._backupErr(LocalBackupErrorCodes.invalidEntry),
            },
          ),
        );
      }
      staging = await Directory.systemTemp.createTemp('plug_restore_');
      final root = staging.path;

      for (final file in archive.files) {
        if (!file.isFile) {
          continue;
        }
        final normalizedName = file.name.replaceAll(r'\', '/');
        if (normalizedName != p.basename(normalizedName)) {
          _deleteDirIfExists(root);
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'Invalid archive path',
              context: _backupErr(LocalBackupErrorCodes.invalidEntry),
            ),
          );
        }
        final base = p.basename(normalizedName);
        if (!_allowedZipBasenames.contains(base)) {
          continue;
        }
        final targetPath = p.join(root, base);
        final data = file.content;
        final List<int> raw;
        if (data is List<int>) {
          raw = data;
        } else if (data is Uint8List) {
          raw = data.toList();
        } else {
          _deleteDirIfExists(root);
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'Invalid archive entry',
              context: _backupErr(LocalBackupErrorCodes.invalidEntry),
            ),
          );
        }
        await File(targetPath).writeAsBytes(raw, flush: true);
      }

      final manifestFile = File(p.join(root, _manifestFileName));
      final dbStaged = File(p.join(root, _dbFileName));
      if (!manifestFile.existsSync() || !dbStaged.existsSync()) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Backup archive is missing manifest or database',
            context: _backupErr(LocalBackupErrorCodes.missingManifestOrDb),
          ),
        );
      }

      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map<String, dynamic>) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Invalid backup manifest',
            context: _backupErr(LocalBackupErrorCodes.invalidManifest),
          ),
        );
      }
      final formatVersion = manifest['formatVersion'];
      if (formatVersion is! int || formatVersion != _backupManifestFormatVersion) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Unsupported backup format version',
            context: _backupErr(LocalBackupErrorCodes.unsupportedFormat),
          ),
        );
      }

      final backupUserVersion = BackupSqliteReader.readUserVersion(dbStaged.path);
      if (backupUserVersion == null) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Could not read database schema version from backup',
            context: _backupErr(LocalBackupErrorCodes.dbVersion),
          ),
        );
      }

      if (backupUserVersion > _database.schemaVersion) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'This backup was created with a newer app version. Update the app before restoring.',
            context: _backupErr(LocalBackupErrorCodes.newerBackup),
          ),
        );
      }

      final stagedSettingsPath = File(p.join(root, _settingsFileName)).existsSync()
          ? p.join(root, _settingsFileName)
          : null;
      final stagedSecretsPath = File(p.join(root, _secureStorageSecretsFileName)).existsSync()
          ? p.join(root, _secureStorageSecretsFileName)
          : null;

      final manifestSecureStorageSecretsIncluded = _manifestSecureStorageSecretsIncluded(manifest);
      final manifestSecureStorageSecretsEntryCount = manifest['secureStorageSecretsEntryCount'] is int
          ? manifest['secureStorageSecretsEntryCount'] as int
          : null;

      if (manifestSecureStorageSecretsIncluded && stagedSecretsPath == null) {
        _deleteDirIfExists(root);
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Backup manifest declares secure storage secrets but the archive is missing the encrypted blob',
            context: _backupErr(LocalBackupErrorCodes.invalidManifest),
          ),
        );
      }

      final hubRow = BackupSqliteReader.readHubRow(dbStaged.path);
      final duplicateRisk = await _resolveDuplicateRisk(hubRow);

      final manifestInstallationId = manifest['installationId'] is String ? manifest['installationId'] as String : null;
      final currentInstallationId = _settingsStore.getString(AppConstants.installationIdSettingsKey);

      final snapshot = RestoreStagingSnapshot(
        tempDirectoryPath: root,
        stagedDatabasePath: dbStaged.path,
        stagedSettingsPath: stagedSettingsPath,
        stagedSecureStorageSecretsPath: stagedSecretsPath,
        backupUserVersion: backupUserVersion,
        duplicateRisk: duplicateRisk,
        manifestInstallationId: manifestInstallationId,
        currentInstallationId: currentInstallationId,
        manifestSecureStorageSecretsIncluded: manifestSecureStorageSecretsIncluded,
        manifestSecureStorageSecretsEntryCount: manifestSecureStorageSecretsEntryCount,
      );

      developer.log(
        'operation=stageRestoreFromZip outcome=success duplicateRisk=${snapshot.duplicateRisk.name}',
        name: 'local_app_data_backup',
      );
      return Success(snapshot);
    } on FormatException catch (e, st) {
      if (staging != null) {
        _deleteDirIfExists(staging.path);
      }
      developer.log(
        'operation=stageRestoreFromZip outcome=failure backupError=${LocalBackupErrorCodes.readZip}',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Could not read backup file',
          context: _backupErr(LocalBackupErrorCodes.readZip),
        ),
      );
    } on Exception catch (e, st) {
      if (staging != null) {
        _deleteDirIfExists(staging.path);
      }
      developer.log(
        'operation=stageRestoreFromZip outcome=failure backupError=${LocalBackupErrorCodes.stageGeneric}',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to read backup archive',
          cause: e,
          context: {
            'operation': 'stageRestoreFromZip',
            ..._backupErr(LocalBackupErrorCodes.stageGeneric),
          },
        ),
      );
    }
  }

  Future<DuplicateRiskLevel> _resolveDuplicateRisk(BackupHubRow? hubRow) async {
    if (hubRow == null || hubRow.agentId.isEmpty || hubRow.serverUrl.isEmpty) {
      return DuplicateRiskLevel.verificationImpossible;
    }
    final serverUrl = hubRow.serverUrl.trim();

    var access = hubRow.authToken?.trim();
    final refresh = hubRow.refreshToken?.trim();

    if ((access == null || access.isEmpty) && (refresh != null && refresh.isNotEmpty)) {
      final refreshed = await _authClient.refreshToken(serverUrl, refresh);
      if (refreshed.isSuccess()) {
        access = refreshed.getOrThrow().token.trim();
      }
    }

    if (access == null || access.isEmpty) {
      return DuplicateRiskLevel.verificationImpossible;
    }

    final listResult = await _connectedAgentsGateway.fetchAgentsList(
      serverUrl: serverUrl,
      accessToken: access,
    );

    return listResult.fold(
      (body) {
        final listed = ConnectedAgentsResponseParser.isAgentIdListedAsConnected(
          body,
          hubRow.agentId.trim(),
        );
        return listed ? DuplicateRiskLevel.agentListedAsConnectedOnHub : DuplicateRiskLevel.none;
      },
      (_) => DuplicateRiskLevel.verificationImpossible,
    );
  }

  @override
  Future<Result<void>> applyRestore(RestoreStagingSnapshot staging) async {
    try {
      _deleteIfExists(_restoreFailureDiagnosticsFile());

      final targetDb = File(_storageContext.databaseFilePath);
      final targetSettings = File(_storageContext.settingsFilePath);
      final stagedDb = File(staging.stagedDatabasePath);

      if (!stagedDb.existsSync()) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Staged database file is missing',
            context: _backupErr(LocalBackupErrorCodes.applyMissingDb),
          ),
        );
      }

      await _copyToBackupSuffix(targetDb);
      await _copyToBackupSuffix(targetSettings);

      _deleteIfExists(File('${targetDb.path}-wal'));
      _deleteIfExists(File('${targetDb.path}-shm'));
      _deleteIfExists(File('${targetSettings.path}.tmp'));

      // Copy to .new temporary files, then rename atomically so a crash
      // mid-copy leaves the .bak files intact and the live files untouched.
      final newDbPath = '${targetDb.path}.new';
      await stagedDb.copy(newDbPath);
      await File(newDbPath).rename(targetDb.path);

      if (staging.stagedSettingsPath != null) {
        final stagedSettings = File(staging.stagedSettingsPath!);
        if (stagedSettings.existsSync()) {
          final newSettingsPath = '${targetSettings.path}.new';
          await stagedSettings.copy(newSettingsPath);
          await File(newSettingsPath).rename(targetSettings.path);
        }
      }

      if (staging.stagedSecureStorageSecretsPath != null) {
        final restoreSecretsResult = await _restoreSecureStorageSecretsFromStagedFile(
          File(staging.stagedSecureStorageSecretsPath!),
        );
        if (restoreSecretsResult.isError()) {
          return restoreSecretsResult;
        }
      }

      developer.log(
        'operation=applyRestore outcome=success secureStorageSecretsRestored=${staging.stagedSecureStorageSecretsPath != null}',
        name: 'local_app_data_backup',
      );
      return const Success(unit);
    } on FileSystemException catch (e, st) {
      developer.log(
        'operation=applyRestore outcome=failure backupError=${LocalBackupErrorCodes.applyWrite}',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Could not apply backup files',
          cause: e,
          context: {
            'operation': 'applyRestore',
            ..._backupErr(LocalBackupErrorCodes.applyWrite),
          },
        ),
      );
    }
  }

  @override
  Future<void> writeRestoreFailureDiagnostics(Object failure) {
    return RestoreFailureDiagnostics.writeFromFailure(
      storage: _storageContext,
      failure: failure,
    );
  }

  @override
  Future<String?> readPendingRestoreFailureDiagnostics() async {
    try {
      final file = _restoreFailureDiagnosticsFile();
      if (!file.existsSync()) {
        return null;
      }
      final content = await file.readAsString();
      return content.trim().isEmpty ? null : content;
    } on Object catch (e, st) {
      developer.log(
        'failed to read ${AppConstants.lastRestoreErrorFileName}',
        name: 'local_app_data_backup_service',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  Future<void> clearRestoreFailureDiagnostics() async {
    _deleteIfExists(_restoreFailureDiagnosticsFile());
  }

  File _restoreFailureDiagnosticsFile() {
    return File(
      p.join(_storageContext.appDirectoryPath, AppConstants.lastRestoreErrorFileName),
    );
  }

  @override
  void disposeStaging(RestoreStagingSnapshot staging) {
    _deleteDirIfExists(staging.tempDirectoryPath);
  }

  Future<Uint8List> _readDbBytesWithCheckpointOrVacuumFallback(File dbFile) async {
    try {
      await _database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      developer.log(
        'operation=readDbForExport outcome=checkpoint_ok',
        name: 'local_app_data_backup',
      );
      return dbFile.readAsBytes();
    } on Object catch (e, st) {
      developer.log(
        'operation=readDbForExport outcome=checkpoint_failed_try_vacuum',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return _readDbBytesViaVacuumIntoOrLive(dbFile);
    }
  }

  Future<Uint8List> _readDbBytesViaVacuumIntoOrLive(File dbFile) async {
    final tempName = 'agent_config_vacuum_${DateTime.now().microsecondsSinceEpoch}.sqlite';
    final tempPath = p.join(_storageContext.appDirectoryPath, tempName);
    try {
      await _database.customStatement('VACUUM INTO ${_sqliteStringLiteral(tempPath)}');
      final bytes = await File(tempPath).readAsBytes();
      developer.log(
        'operation=vacuumIntoExport outcome=success',
        name: 'local_app_data_backup',
      );
      return bytes;
    } on Object catch (e, st) {
      developer.log(
        'operation=vacuumIntoExport outcome=failure_using_live_file',
        name: 'local_app_data_backup',
        error: e,
        stackTrace: st,
      );
      return dbFile.readAsBytes();
    } finally {
      _deleteIfExists(File(tempPath));
    }
  }

  String _sqliteStringLiteral(String nativePath) {
    final normalized = nativePath.replaceAll(r'\', '/');
    return "'${normalized.replaceAll("'", "''")}'";
  }

  Future<Result<void>> _restoreSecureStorageSecretsFromStagedFile(File stagedSecretsFile) async {
    if (!_secureStorageSecretsPort.isAvailable) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Secure storage is not available to restore backup secrets',
          context: {
            'operation': 'applyRestore',
            ..._backupErr(LocalBackupErrorCodes.restoreSecretsApply),
          },
        ),
      );
    }

    try {
      final envelopeBytes = await stagedSecretsFile.readAsBytes();
      final entries = await BackupSecureStorageSecretsCipher.decryptEntries(envelopeBytes);
      final restoreResult = await _secureStorageSecretsPort.restoreBackupEligibleEntries(entries);
      if (restoreResult.isError()) {
        final failure = restoreResult.exceptionOrNull()!;
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Could not apply secure storage secrets from backup',
            cause: failure is domain.Failure ? failure.cause : failure,
            context: {
              'operation': 'applyRestore',
              ..._backupErr(LocalBackupErrorCodes.restoreSecretsApply),
            },
          ),
        );
      }
      return const Success(unit);
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'operation=applyRestore outcome=failure backupError=${LocalBackupErrorCodes.restoreSecretsDecrypt}',
        name: 'local_app_data_backup',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Could not decrypt secure storage secrets from backup',
          cause: error,
          context: {
            'operation': 'applyRestore',
            ..._backupErr(LocalBackupErrorCodes.restoreSecretsDecrypt),
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'operation=applyRestore outcome=failure backupError=${LocalBackupErrorCodes.restoreSecretsDecrypt}',
        name: 'local_app_data_backup',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to restore secure storage secrets from backup',
          cause: error,
          context: {
            'operation': 'applyRestore',
            ..._backupErr(LocalBackupErrorCodes.restoreSecretsDecrypt),
          },
        ),
      );
    }
  }

  bool _manifestSecureStorageSecretsIncluded(Map<String, dynamic> manifest) {
    final secureStorageFlag = manifest['secureStorageSecretsIncluded'];
    if (secureStorageFlag is bool) {
      return secureStorageFlag;
    }
    final legacyFlag = manifest['odbcSecretsIncluded'];
    return legacyFlag is bool && legacyFlag;
  }

  Future<Uint8List?> _encodeZipPayload({
    required Uint8List manifestBytes,
    required Uint8List dbBytes,
    required Uint8List? settingsBytes,
    required Uint8List? secureStorageSecretsBytes,
    required int payloadBytes,
  }) async {
    final parts = BackupZipEncodeParts(
      manifestBytes: manifestBytes,
      dbBytes: dbBytes,
      settingsBytes: settingsBytes,
      secureStorageSecretsBytes: secureStorageSecretsBytes,
      secureStorageSecretsFileName: secureStorageSecretsBytes == null ? null : _secureStorageSecretsFileName,
    );
    if (payloadBytes >= _backupExportIsolateMinBytes) {
      developer.log(
        'operation=encodeZip isolate=true payloadBytes=$payloadBytes',
        name: 'local_app_data_backup',
      );
      return Isolate.run(() => encodeBackupZipBytes(parts));
    }
    developer.log(
      'operation=encodeZip isolate=false payloadBytes=$payloadBytes',
      name: 'local_app_data_backup',
    );
    return encodeBackupZipBytes(parts);
  }

  Future<String> _ensureInstallationId() async {
    final existing = _settingsStore.getString(AppConstants.installationIdSettingsKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final id = const Uuid().v4();
    await _settingsStore.setString(AppConstants.installationIdSettingsKey, id);
    return id;
  }

  Future<void> _copyToBackupSuffix(File file) async {
    if (!file.existsSync()) {
      return;
    }
    final bak = File('${file.path}.bak');
    if (bak.existsSync()) {
      await bak.delete();
    }
    await file.copy(bak.path);
  }

  void _deleteIfExists(File f) {
    if (f.existsSync()) {
      f.deleteSync();
    }
  }

  void _deleteDirIfExists(String path) {
    final d = Directory(path);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  }
}

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/backup/backup_sqlite_reader.dart';
import 'package:plug_agente/infrastructure/backup/connected_agents_response_parser.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

const int _backupManifestFormatVersion = 1;
const String _manifestFileName = 'manifest.json';
const String _dbFileName = 'agent_config.db';
const String _settingsFileName = 'settings.json';

const Set<String> _allowedZipBasenames = {
  _manifestFileName,
  _dbFileName,
  _settingsFileName,
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
  }) : _database = database,
       _storageContext = storageContext,
       _settingsStore = settingsStore,
       _authClient = authClient,
       _connectedAgentsGateway = connectedAgentsGateway;

  final AppDatabase _database;
  final GlobalStorageContext _storageContext;
  final IAppSettingsStore _settingsStore;
  final IAuthClient _authClient;
  final IConnectedAgentsGateway _connectedAgentsGateway;

  @override
  int get liveAgentConfigSchemaVersion => _database.schemaVersion;

  @override
  Future<Result<void>> exportBackupZip(String destinationZipPath) async {
    final out = File(destinationZipPath);
    try {
      developer.log('local_backup export start', name: 'local_app_data_backup');
      await _database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

      final installationId = await _ensureInstallationId();
      final manifest = <String, dynamic>{
        'formatVersion': _backupManifestFormatVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': AppConstants.appVersion,
        'platform': Platform.operatingSystem,
        'installationId': installationId,
      };

      final dbFile = File(_storageContext.databaseFilePath);
      final settingsFile = File(_storageContext.settingsFilePath);

      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          _manifestFileName,
          utf8.encode(jsonEncode(manifest)).length,
          utf8.encode(jsonEncode(manifest)),
        ),
      );

      if (!dbFile.existsSync()) {
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
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile(_dbFileName, dbBytes.length, dbBytes));

      if (settingsFile.existsSync()) {
        final sBytes = await settingsFile.readAsBytes();
        archive.addFile(ArchiveFile(_settingsFileName, sBytes.length, sBytes));
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
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
      await out.writeAsBytes(zipBytes, flush: true);
      developer.log('local_backup export done', name: 'local_app_data_backup');
      return const Success(unit);
    } on FileSystemException catch (e, st) {
      developer.log(
        'local_backup export failed',
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
        'local_backup export failed',
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
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
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

      final hubRow = BackupSqliteReader.readHubRow(dbStaged.path);
      final duplicateRisk = await _resolveDuplicateRisk(hubRow);

      final manifestInstallationId = manifest['installationId'] is String
          ? manifest['installationId'] as String
          : null;
      final currentInstallationId = _settingsStore.getString(AppConstants.installationIdSettingsKey);

      return Success(
        RestoreStagingSnapshot(
          tempDirectoryPath: root,
          stagedDatabasePath: dbStaged.path,
          stagedSettingsPath: stagedSettingsPath,
          backupUserVersion: backupUserVersion,
          duplicateRisk: duplicateRisk,
          manifestInstallationId: manifestInstallationId,
          currentInstallationId: currentInstallationId,
        ),
      );
    } on FormatException catch (e, st) {
      if (staging != null) {
        _deleteDirIfExists(staging.path);
      }
      developer.log(
        'local_backup stage failed',
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
        'local_backup stage failed',
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

      await stagedDb.copy(targetDb.path);

      if (staging.stagedSettingsPath != null) {
        final stagedSettings = File(staging.stagedSettingsPath!);
        if (stagedSettings.existsSync()) {
          if (targetSettings.existsSync()) {
            await targetSettings.delete();
          }
          await stagedSettings.copy(targetSettings.path);
        }
      }

      developer.log('local_backup apply done', name: 'local_app_data_backup');
      return const Success(unit);
    } on FileSystemException catch (e, st) {
      developer.log(
        'local_backup apply failed',
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
  void disposeStaging(RestoreStagingSnapshot staging) {
    _deleteDirIfExists(staging.tempDirectoryPath);
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

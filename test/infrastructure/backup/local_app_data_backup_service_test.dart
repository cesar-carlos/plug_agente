import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/backup/backup_secure_storage_secrets_constants.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_backup_secure_storage_secrets_port.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/backup/backup_secure_storage_secrets_cipher.dart';
import 'package:plug_agente/infrastructure/backup/connected_agents_response_parser.dart';
import 'package:plug_agente/infrastructure/backup/local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/batch_secret_store_mixin.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';
import 'package:result_dart/result_dart.dart';
import 'package:sqlite3/sqlite3.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockAuthClient extends Mock implements IAuthClient {}

class MockAgentsGateway extends Mock implements IConnectedAgentsGateway {}

class _FakeBackupSecureStorageSecretsPort implements IBackupSecureStorageSecretsPort {
  _FakeBackupSecureStorageSecretsPort({
    this.isAvailable = true,
    Map<String, String>? entries,
  }) : _entries = Map<String, String>.from(entries ?? const <String, String>{});

  final Map<String, String> _entries;
  @override
  final bool isAvailable;
  Map<String, String> restoredEntries = <String, String>{};

  @override
  Future<Result<Map<String, String>>> readBackupEligibleEntries() async {
    if (!isAvailable) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Secure storage unavailable',
          context: const {'operation': 'readBackupEligibleEntries'},
        ),
      );
    }
    return Success(Map<String, String>.from(_entries));
  }

  @override
  Future<Result<void>> restoreBackupEligibleEntries(Map<String, String> entries) async {
    if (!isAvailable) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Secure storage unavailable',
          context: const {'operation': 'restoreBackupEligibleEntries'},
        ),
      );
    }
    restoredEntries = Map<String, String>.from(entries);
    _entries
      ..clear()
      ..addAll(entries);
    return const Success(unit);
  }
}

class _FakeOdbcCredentialSecretStore
    with BatchOdbcCredentialSecretStoreMixin
    implements IOdbcCredentialSecretStore {
  final Map<String, OdbcCredentialSecrets> _storage = <String, OdbcCredentialSecrets>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<OdbcCredentialSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const OdbcCredentialSecrets();
  }

  @override
  Future<void> saveSecrets(String configId, OdbcCredentialSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue('');
  });

  group('ConnectedAgentsResponseParser', () {
    test('returns true when agent id matches and no explicit offline flag', () {
      const body = '[{"id":"a1","name":"x"}]';
      expect(ConnectedAgentsResponseParser.isAgentIdListedAsConnected(body, 'a1'), isTrue);
    });

    test('returns false when connected is false', () {
      const body = '[{"id":"a1","connected":false}]';
      expect(ConnectedAgentsResponseParser.isAgentIdListedAsConnected(body, 'a1'), isFalse);
    });

    test('returns false when agent id not in list', () {
      const body = '[{"id":"other"}]';
      expect(ConnectedAgentsResponseParser.isAgentIdListedAsConnected(body, 'a1'), isFalse);
    });
  });

  group('LocalAppDataBackupService', () {
    late Directory tempRoot;
    late MockAppDatabase mockDb;
    late InMemoryAppSettingsStore settingsStore;
    late MockAuthClient mockAuth;
    late MockAgentsGateway mockGateway;
    late _FakeBackupSecureStorageSecretsPort fakeSecretsPort;
    late LocalAppDataBackupService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('plug_backup_test_');
      mockDb = MockAppDatabase();
      when(() => mockDb.customStatement(any())).thenAnswer((_) async {});
      when(() => mockDb.schemaVersion).thenReturn(30);
      settingsStore = InMemoryAppSettingsStore();
      mockAuth = MockAuthClient();
      mockGateway = MockAgentsGateway();
      fakeSecretsPort = _FakeBackupSecureStorageSecretsPort();
      service = LocalAppDataBackupService(
        database: mockDb,
        storageContext: GlobalStorageContext(appDirectoryPath: tempRoot.path),
        settingsStore: settingsStore,
        authClient: mockAuth,
        connectedAgentsGateway: mockGateway,
        secureStorageSecretsPort: fakeSecretsPort,
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('liveAgentConfigSchemaVersion reflects database schema', () {
      expect(service.liveAgentConfigSchemaVersion, 30);
    });

    test('exportBackupZip does not include flutter_secure_storage', () async {
      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 28);
      await File(p.join(tempRoot.path, 'settings.json')).writeAsString('{}');
      await File(p.join(tempRoot.path, 'flutter_secure_storage.dat')).writeAsString(
        'encrypted-odbc-secrets-not-for-backup',
      );

      final outPath = p.join(tempRoot.path, 'out.zip');
      final result = await service.exportBackupZip(outPath);

      expect(result.isSuccess(), isTrue);

      final archive = ZipDecoder().decodeBytes(await File(outPath).readAsBytes());
      final names = archive.files.where((f) => f.isFile).map((f) => f.name).toSet();
      expect(names, containsAll(<String>['manifest.json', 'agent_config.db', 'settings.json']));
      expect(names.any((name) => name.contains('flutter_secure_storage')), isFalse);
      expect(names.length, 3);
    });

    test('exportBackupZip manifest documents ODBC secrets are not included', () async {
      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 28);
      await File(p.join(tempRoot.path, 'settings.json')).writeAsString('{}');

      final outPath = p.join(tempRoot.path, 'manifest.zip');
      final result = await service.exportBackupZip(outPath);

      expect(result.isSuccess(), isTrue);

      final archive = ZipDecoder().decodeBytes(await File(outPath).readAsBytes());
      final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
      final manifest = jsonDecode(String.fromCharCodes(manifestFile.content as List<int>)) as Map<String, dynamic>;
      expect(manifest['odbcSecretsIncluded'], isFalse);
      expect(manifest['secureStorageSecretsIncluded'], isFalse);
    });

    test('exportBackupZip with opt-in includes encrypted secure storage secrets blob', () async {
      fakeSecretsPort = _FakeBackupSecureStorageSecretsPort(
        entries: <String, String>{
          'odbc_credential_secret_cfg-1_password': 'odbc-secret',
          'hub_auth_secret_cfg-1_auth_token': 'hub-token',
        },
      );
      service = LocalAppDataBackupService(
        database: mockDb,
        storageContext: GlobalStorageContext(appDirectoryPath: tempRoot.path),
        settingsStore: settingsStore,
        authClient: mockAuth,
        connectedAgentsGateway: mockGateway,
        secureStorageSecretsPort: fakeSecretsPort,
      );

      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 28);
      await File(p.join(tempRoot.path, 'settings.json')).writeAsString('{}');

      final outPath = p.join(tempRoot.path, 'with-secrets.zip');
      final result = await service.exportBackupZip(
        outPath,
        includeSecureStorageSecrets: true,
      );

      expect(result.isSuccess(), isTrue);

      final archive = ZipDecoder().decodeBytes(await File(outPath).readAsBytes());
      final names = archive.files.where((f) => f.isFile).map((f) => f.name).toSet();
      expect(names, contains(BackupSecureStorageSecretsConstants.zipEntryFileName));
      expect(names.length, 4);

      final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
      final manifest = jsonDecode(String.fromCharCodes(manifestFile.content as List<int>)) as Map<String, dynamic>;
      expect(manifest['odbcSecretsIncluded'], isTrue);
      expect(manifest['secureStorageSecretsIncluded'], isTrue);
      expect(manifest['secureStorageSecretsBlobVersion'], 1);
      expect(manifest['secureStorageSecretsEntryCount'], 2);

      final secretsFile = archive.files.firstWhere(
        (f) => f.name == BackupSecureStorageSecretsConstants.zipEntryFileName,
      );
      final decrypted = await BackupSecureStorageSecretsCipher.decryptEntries(
        Uint8List.fromList(secretsFile.content as List<int>),
      );
      expect(decrypted['odbc_credential_secret_cfg-1_password'], 'odbc-secret');
      expect(decrypted['hub_auth_secret_cfg-1_auth_token'], 'hub-token');
      expect(utf8.decode(secretsFile.content as List<int>).contains('odbc-secret'), isFalse);
    });

    test('exportBackupZip opt-in fails when secure storage port is unavailable', () async {
      fakeSecretsPort = _FakeBackupSecureStorageSecretsPort(isAvailable: false);
      service = LocalAppDataBackupService(
        database: mockDb,
        storageContext: GlobalStorageContext(appDirectoryPath: tempRoot.path),
        settingsStore: settingsStore,
        authClient: mockAuth,
        connectedAgentsGateway: mockGateway,
        secureStorageSecretsPort: fakeSecretsPort,
      );

      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 28);

      final result = await service.exportBackupZip(
        p.join(tempRoot.path, 'fail.zip'),
        includeSecureStorageSecrets: true,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context[LocalBackupErrorCodes.contextKey], LocalBackupErrorCodes.exportSecretsUnavailable);
    });

    test('exportBackupZip runs wal_checkpoint and includes manifest db and settings', () async {
      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 28);
      await File(p.join(tempRoot.path, 'settings.json')).writeAsString('{"k":1}');
      await settingsStore.setString(AppConstants.installationIdSettingsKey, 'inst-test');

      final outPath = p.join(tempRoot.path, 'out.zip');
      final result = await service.exportBackupZip(outPath);

      expect(result.isSuccess(), isTrue);
      verify(() => mockDb.customStatement('PRAGMA wal_checkpoint(TRUNCATE)')).called(1);

      final archive = ZipDecoder().decodeBytes(await File(outPath).readAsBytes());
      final names = archive.files.where((f) => f.isFile).map((f) => f.name).toSet();
      expect(names, containsAll(<String>['manifest.json', 'agent_config.db', 'settings.json']));

      final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
      final manifest = jsonDecode(String.fromCharCodes(manifestFile.content as List<int>)) as Map<String, dynamic>;
      expect(manifest['formatVersion'], 1);
      expect(manifest['installationId'], 'inst-test');
    });

    test('stageRestoreFromZip rejects nested paths zip-slip', () async {
      final dbPath = p.join(tempRoot.path, 'source.db');
      _writeAgentConfigDb(dbPath, userVersion: 10);

      final dbBytes = await File(dbPath).readAsBytes();
      final manifest = utf8.encode(jsonEncode(_validManifest()));
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('nested/agent_config.db', dbBytes.length, dbBytes));
      final zipPath = p.join(tempRoot.path, 'slip.zip');
      await File(zipPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)!));

      final result = await service.stageRestoreFromZip(zipPath);

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context[LocalBackupErrorCodes.contextKey], LocalBackupErrorCodes.invalidEntry);
    });

    test('stageRestoreFromZip fails when backup user_version is newer than app', () async {
      final dbPath = p.join(tempRoot.path, 'newer.db');
      _writeAgentConfigDb(dbPath, userVersion: 99);
      await _writeZip(
        p.join(tempRoot.path, 'newer.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
      );

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'newer.zip'));

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context[LocalBackupErrorCodes.contextKey], LocalBackupErrorCodes.newerBackup);
    });

    test('stageRestoreFromZip returns none when hub lists no matching agent', () async {
      final dbPath = p.join(tempRoot.path, 'hub.db');
      _writeAgentConfigDb(
        dbPath,
        userVersion: 10,
        agentId: 'agent-x',
        accessToken: 'tok',
      );
      await _writeZip(
        p.join(tempRoot.path, 'ok.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
      );

      when(
        () => mockGateway.fetchAgentsList(
          serverUrl: any(named: 'serverUrl'),
          accessToken: any(named: 'accessToken'),
        ),
      ).thenAnswer((_) async => const Success('[{"id":"other"}]'));

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'ok.zip'));

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().duplicateRisk, DuplicateRiskLevel.none);
    });

    test('stageRestoreFromZip duplicate check works when ODBC password column is null', () async {
      final dbPath = p.join(tempRoot.path, 'migrated-hub.db');
      _writeAgentConfigDb(
        dbPath,
        userVersion: 28,
        agentId: 'agent-migrated',
        accessToken: 'tok',
        connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa',
      );
      await _writeZip(
        p.join(tempRoot.path, 'migrated-hub.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
      );

      when(
        () => mockGateway.fetchAgentsList(
          serverUrl: any(named: 'serverUrl'),
          accessToken: any(named: 'accessToken'),
        ),
      ).thenAnswer(
        (_) async => const Success('[{"id":"agent-migrated","connected":true}]'),
      );

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'migrated-hub.zip'));

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().duplicateRisk, DuplicateRiskLevel.agentListedAsConnectedOnHub);
    });

    test('stageRestoreFromZip returns duplicate risk when hub lists agent as connected', () async {
      final dbPath = p.join(tempRoot.path, 'dup.db');
      _writeAgentConfigDb(
        dbPath,
        userVersion: 10,
        agentId: 'agent-dup',
        accessToken: 'tok',
      );
      await _writeZip(
        p.join(tempRoot.path, 'dup.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
      );

      when(
        () => mockGateway.fetchAgentsList(
          serverUrl: any(named: 'serverUrl'),
          accessToken: any(named: 'accessToken'),
        ),
      ).thenAnswer(
        (_) async => const Success('[{"id":"agent-dup","connected":true}]'),
      );

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'dup.zip'));

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().duplicateRisk, DuplicateRiskLevel.agentListedAsConnectedOnHub);
    });

    test('stageRestoreFromZip uses refresh when access token empty', () async {
      final dbPath = p.join(tempRoot.path, 'refresh.db');
      _writeAgentConfigDb(
        dbPath,
        userVersion: 10,
        agentId: 'agent-r',
        refreshToken: 'refresh-1',
      );
      await _writeZip(
        p.join(tempRoot.path, 'refresh.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
      );

      when(() => mockAuth.refreshToken(any(), any())).thenAnswer(
        (_) async => const Success(AuthToken(token: 'new-access', refreshToken: 'refresh-1')),
      );
      when(
        () => mockGateway.fetchAgentsList(
          serverUrl: any(named: 'serverUrl'),
          accessToken: any(named: 'accessToken'),
        ),
      ).thenAnswer((_) async => const Success('[]'));

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'refresh.zip'));

      expect(result.isSuccess(), isTrue);
      verify(() => mockAuth.refreshToken('https://hub.example', 'refresh-1')).called(1);
    });

    test('applyRestore copies db removes wal shm and settings tmp', () async {
      final targetDb = File(p.join(tempRoot.path, 'agent_config.db'));
      await targetDb.writeAsBytes(utf8.encode('old'));
      await File('${targetDb.path}-wal').writeAsString('wal');
      await File('${targetDb.path}-shm').writeAsString('shm');
      await File(p.join(tempRoot.path, 'settings.json')).writeAsString('{}');
      await File(p.join(tempRoot.path, 'settings.json.tmp')).writeAsString('tmp');

      final stageDir = await Directory.systemTemp.createTemp('plug_apply_');
      final stagedDbPath = p.join(stageDir.path, 'agent_config.db');
      _writeAgentConfigDb(stagedDbPath, userVersion: 8);
      final stagedSettings = File(p.join(stageDir.path, 'settings.json'));
      await stagedSettings.writeAsString('{"restored":true}');

      addTearDown(() async {
        if (stageDir.existsSync()) {
          await stageDir.delete(recursive: true);
        }
      });

      final snapshot = RestoreStagingSnapshot(
        tempDirectoryPath: stageDir.path,
        stagedDatabasePath: stagedDbPath,
        stagedSettingsPath: stagedSettings.path,
        backupUserVersion: 8,
        duplicateRisk: DuplicateRiskLevel.none,
      );

      final applyResult = await service.applyRestore(snapshot);
      service.disposeStaging(snapshot);

      expect(applyResult.isSuccess(), isTrue);
      expect(File('${targetDb.path}-wal').existsSync(), isFalse);
      expect(File('${targetDb.path}-shm').existsSync(), isFalse);
      expect(File(p.join(tempRoot.path, 'settings.json.tmp')).existsSync(), isFalse);

      final reopened = sqlite3.open(targetDb.path, mode: OpenMode.readOnly);
      try {
        final row = reopened.select('PRAGMA user_version').first;
        expect(row.values.first, 8);
      } finally {
        reopened.dispose();
      }

      expect(jsonDecode(await File(p.join(tempRoot.path, 'settings.json')).readAsString()), {'restored': true});
      expect(File('${targetDb.path}.bak').existsSync(), isTrue);
    });

    test(
      'applyRestore of migrated ODBC row leaves credentials empty until reconfigured',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp('plug_backup_migrated_');
        addTearDown(() async {
          if (sourceDir.existsSync()) {
            await sourceDir.delete(recursive: true);
          }
        });

        final sourceDbPath = p.join(sourceDir.path, 'agent_config.db');
        await _writeDriftConfigDb(
          sourceDbPath,
          configId: 'cfg-migrated',
          connectionString:
              'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa',
        );

        final zipPath = p.join(sourceDir.path, 'backup.zip');
        await _writeZip(
          zipPath,
          dbBytes: await File(sourceDbPath).readAsBytes(),
        );

        final stageResult = await service.stageRestoreFromZip(zipPath);
        expect(stageResult.isSuccess(), isTrue);
        final snapshot = stageResult.getOrThrow();

        final applyResult = await service.applyRestore(snapshot);
        service.disposeStaging(snapshot);
        expect(applyResult.isSuccess(), isTrue);

        final odbcSecretStore = _FakeOdbcCredentialSecretStore();
        final restoredDb = _openFileDatabase(p.join(tempRoot.path, 'agent_config.db'));
        final odbcStore = OdbcCredentialStore(
          restoredDb,
          credentialSecretStore: odbcSecretStore,
        );

        final credentials = await odbcStore.readCredentials('cfg-migrated');
        expect(credentials.isSuccess(), isTrue);
        expect(credentials.getOrThrow().password, isNull);
        expect((await odbcSecretStore.readSecrets('cfg-migrated')).hasAny, isFalse);
      },
    );

    test('applyRestore of legacy ODBC row lazy migrates password on read', () async {
      final sourceDir = await Directory.systemTemp.createTemp('plug_backup_legacy_');
      addTearDown(() async {
        if (sourceDir.existsSync()) {
          await sourceDir.delete(recursive: true);
        }
      });

      final sourceDbPath = p.join(sourceDir.path, 'agent_config.db');
      await _writeDriftConfigDb(
        sourceDbPath,
        configId: 'cfg-legacy',
        connectionString: 'DRIVER={x};PWD=legacy-db-secret',
      );

      final zipPath = p.join(sourceDir.path, 'backup.zip');
      await _writeZip(
        zipPath,
        dbBytes: await File(sourceDbPath).readAsBytes(),
      );

      final stageResult = await service.stageRestoreFromZip(zipPath);
      expect(stageResult.isSuccess(), isTrue);
      final snapshot = stageResult.getOrThrow();

      final applyResult = await service.applyRestore(snapshot);
      service.disposeStaging(snapshot);
      expect(applyResult.isSuccess(), isTrue);

      final odbcSecretStore = _FakeOdbcCredentialSecretStore();
      final restoredDb = _openFileDatabase(p.join(tempRoot.path, 'agent_config.db'));
      final odbcStore = OdbcCredentialStore(
        restoredDb,
        credentialSecretStore: odbcSecretStore,
      );

      final credentials = await odbcStore.readCredentials('cfg-legacy');
      expect(credentials.isSuccess(), isTrue);
      expect(credentials.getOrThrow().password, 'legacy-db-secret');
      expect(
        (await odbcSecretStore.readSecrets('cfg-legacy')).password,
        'legacy-db-secret',
      );

      final row = await (restoredDb.select(restoredDb.configTable)
            ..where((tbl) => tbl.id.equals('cfg-legacy')))
          .getSingle();
      expect(row.connectionString, isNot(contains('PWD=')));
    });

    test('applyRestore restores encrypted secure storage secrets when blob is staged', () async {
      final secretsEntries = <String, String>{
        'odbc_credential_secret_cfg-restored_password': 'restored-secret',
      };
      final encrypted = await BackupSecureStorageSecretsCipher.encryptEntries(secretsEntries);

      final stageDir = await Directory.systemTemp.createTemp('plug_apply_secrets_');
      final stagedDbPath = p.join(stageDir.path, 'agent_config.db');
      _writeAgentConfigDb(stagedDbPath, userVersion: 8);
      await File(p.join(stageDir.path, BackupSecureStorageSecretsConstants.zipEntryFileName)).writeAsBytes(encrypted);

      addTearDown(() async {
        if (stageDir.existsSync()) {
          await stageDir.delete(recursive: true);
        }
      });

      final snapshot = RestoreStagingSnapshot(
        tempDirectoryPath: stageDir.path,
        stagedDatabasePath: stagedDbPath,
        stagedSecureStorageSecretsPath: p.join(
          stageDir.path,
          BackupSecureStorageSecretsConstants.zipEntryFileName,
        ),
        backupUserVersion: 8,
        duplicateRisk: DuplicateRiskLevel.none,
        manifestSecureStorageSecretsIncluded: true,
        manifestSecureStorageSecretsEntryCount: 1,
      );

      final applyResult = await service.applyRestore(snapshot);
      service.disposeStaging(snapshot);

      expect(applyResult.isSuccess(), isTrue);
      expect(fakeSecretsPort.restoredEntries, secretsEntries);
    });

    test('stageRestoreFromZip rejects manifest that declares secrets without blob', () async {
      final dbPath = p.join(tempRoot.path, 'missing-blob.db');
      _writeAgentConfigDb(dbPath, userVersion: 10);
      await _writeZip(
        p.join(tempRoot.path, 'missing-blob.zip'),
        dbBytes: await File(dbPath).readAsBytes(),
        manifest: _validManifest(
          secureStorageSecretsIncluded: true,
          secureStorageSecretsEntryCount: 1,
        ),
      );

      final result = await service.stageRestoreFromZip(p.join(tempRoot.path, 'missing-blob.zip'));

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context[LocalBackupErrorCodes.contextKey], LocalBackupErrorCodes.invalidManifest);
    });

    test('disposeStaging removes staging directory', () {
      final stageDir = Directory.systemTemp.createTempSync('plug_dispose_staging_');
      final inner = File(p.join(stageDir.path, 'agent_config.db'));
      inner.writeAsStringSync('x');
      final snapshot = RestoreStagingSnapshot(
        tempDirectoryPath: stageDir.path,
        stagedDatabasePath: inner.path,
        backupUserVersion: 1,
        duplicateRisk: DuplicateRiskLevel.none,
      );

      service.disposeStaging(snapshot);

      expect(stageDir.existsSync(), isFalse);
    });
  });
}

Map<String, dynamic> _validManifest({
  bool secureStorageSecretsIncluded = false,
  int? secureStorageSecretsEntryCount,
}) =>
    <String, dynamic>{
      'formatVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': 'test',
      'platform': 'windows',
      'installationId': 'inst-test',
      'odbcSecretsIncluded': secureStorageSecretsIncluded,
      'secureStorageSecretsIncluded': secureStorageSecretsIncluded,
      if (secureStorageSecretsIncluded) ...<String, dynamic>{
        'secureStorageSecretsBlobVersion': 1,
        'secureStorageSecretsEntryCount': secureStorageSecretsEntryCount ?? 1,
      },
    };

Future<void> _writeZip(
  String zipPath, {
  required Uint8List dbBytes,
  Map<String, dynamic>? manifest,
  Uint8List? secureStorageSecretsBytes,
}) async {
  final manifestBytes = utf8.encode(jsonEncode(manifest ?? _validManifest()));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile('agent_config.db', dbBytes.length, dbBytes));
  if (secureStorageSecretsBytes != null) {
    archive.addFile(
      ArchiveFile(
        BackupSecureStorageSecretsConstants.zipEntryFileName,
        secureStorageSecretsBytes.length,
        secureStorageSecretsBytes,
      ),
    );
  }
  await File(zipPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)!));
}

AppDatabase _openFileDatabase(String path) {
  final database = AppDatabase(executor: NativeDatabase(File(path)));
  addTearDown(database.close);
  return database;
}

Future<void> _writeDriftConfigDb(
  String path, {
  required String configId,
  required String connectionString,
}) async {
  final database = AppDatabase(executor: NativeDatabase(File(path)));
  final now = DateTime.utc(2025);
  try {
    await database
        .into(database.configTable)
        .insert(
          ConfigTableCompanion.insert(
            id: configId,
            serverUrl: const Value('https://hub.example.com'),
            agentId: const Value('agent-1'),
            driverName: 'SQL Server',
            odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
            connectionString: connectionString,
            username: 'sa',
            databaseName: 'demo',
            host: 'localhost',
            port: 1433,
            createdAt: now,
            updatedAt: now,
          ),
        );
  } finally {
    await database.close();
  }
}

void _writeAgentConfigDb(
  String path, {
  required int userVersion,
  String? agentId,
  String serverUrl = 'https://hub.example',
  String? accessToken,
  String? refreshToken,
  String? password,
  String? connectionString,
}) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('''
CREATE TABLE config_table (
  id TEXT,
  agent_id TEXT,
  server_url TEXT,
  auth_token TEXT,
  refresh_token TEXT,
  connection_string TEXT,
  password TEXT,
  updated_at INTEGER
);
''');
    if (agentId != null) {
      final stmt = db.prepare(
        'INSERT INTO config_table (id, agent_id, server_url, auth_token, refresh_token, '
        'connection_string, password, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      stmt.execute([
        agentId,
        agentId,
        serverUrl,
        accessToken,
        refreshToken,
        connectionString,
        password,
        1,
      ]);
      stmt.dispose();
    }
  } finally {
    db.dispose();
  }
}

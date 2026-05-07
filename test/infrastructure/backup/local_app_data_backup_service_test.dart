import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/infrastructure/backup/connected_agents_response_parser.dart';
import 'package:plug_agente/infrastructure/backup/local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';
import 'package:sqlite3/sqlite3.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockAuthClient extends Mock implements IAuthClient {}

class MockAgentsGateway extends Mock implements IConnectedAgentsGateway {}

void main() {
  setUpAll(() {
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
    late LocalAppDataBackupService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('plug_backup_test_');
      mockDb = MockAppDatabase();
      when(() => mockDb.customStatement(any())).thenAnswer((_) async {});
      when(() => mockDb.schemaVersion).thenReturn(13);
      settingsStore = InMemoryAppSettingsStore();
      mockAuth = MockAuthClient();
      mockGateway = MockAgentsGateway();
      service = LocalAppDataBackupService(
        database: mockDb,
        storageContext: GlobalStorageContext(appDirectoryPath: tempRoot.path),
        settingsStore: settingsStore,
        authClient: mockAuth,
        connectedAgentsGateway: mockGateway,
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('liveAgentConfigSchemaVersion reflects database schema', () {
      expect(service.liveAgentConfigSchemaVersion, 13);
    });

    test('exportBackupZip runs wal_checkpoint and includes manifest db and settings', () async {
      final dbPath = p.join(tempRoot.path, 'agent_config.db');
      _writeAgentConfigDb(dbPath, userVersion: 13);
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

Map<String, dynamic> _validManifest() => <String, dynamic>{
  'formatVersion': 1,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'appVersion': 'test',
};

Future<void> _writeZip(String zipPath, {required Uint8List dbBytes}) async {
  final manifest = utf8.encode(jsonEncode(_validManifest()));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
    ..addFile(ArchiveFile('agent_config.db', dbBytes.length, dbBytes));
  await File(zipPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)!));
}

void _writeAgentConfigDb(
  String path, {
  required int userVersion,
  String? agentId,
  String serverUrl = 'https://hub.example',
  String? accessToken,
  String? refreshToken,
}) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = $userVersion');
    db.execute('''
CREATE TABLE config_table (
  agent_id TEXT,
  server_url TEXT,
  auth_token TEXT,
  refresh_token TEXT,
  updated_at INTEGER
);
''');
    if (agentId != null) {
      final stmt = db.prepare(
        'INSERT INTO config_table (agent_id, server_url, auth_token, refresh_token, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
      );
      stmt.execute([agentId, serverUrl, accessToken, refreshToken, 1]);
      stmt.dispose();
    }
  } finally {
    db.dispose();
  }
}

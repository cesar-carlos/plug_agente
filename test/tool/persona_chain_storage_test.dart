import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/config.dart';

import '../../tool/homologation/persona_chain_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final windowsDpapiRequired = !Platform.isWindows ? 'Windows DPAPI fixture is required.' : false;
  late Directory session;
  late ChainAgentStorage storage;
  final initial = Config(
    id: 'isolated-config',
    agentId: 'isolated-agent',
    serverUrl: 'http://127.0.0.1:3131',
    driverName: 'postgres',
    odbcDriverName: 'fixture',
    connectionString: 'DRIVER={fixture};DATABASE=isolated;UID=fixture;PWD=private-odbc-password',
    username: 'fixture',
    databaseName: 'isolated',
    host: '127.0.0.1',
    port: 3132,
    authToken: 'private-auth-token',
    refreshToken: 'private-refresh-token',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  setUp(() {
    if (windowsDpapiRequired != false) {
      return;
    }
    session = Directory.systemTemp.createTempSync('se7e-chain-vault-test-');
    registerChainVault(session);
    storage = ChainAgentStorage(session.path, 'postgres');
  });
  tearDown(() async {
    if (windowsDpapiRequired != false) {
      return;
    }
    await storage.database.close();
    debugDefaultTargetPlatformOverride = null;
    session.deleteSync(recursive: true);
  });
  test('native DPAPI vault restores secrets and stable identities with metadata-only SQLite', () async {
    final saved = await storage.open(initial, 'fixture-client');
    final token = storage.tokenValue;
    final tokenId = storage.tokenId;
    final ciphertext = File('${session.path}/vault/flutter_secure_storage.dat').readAsBytesSync();
    final raw = latin1.decode(ciphertext);
    expect(raw.contains('private-odbc-password'), isFalse);
    expect(raw.contains('private-auth-token'), isFalse);
    expect(raw.contains(token), isFalse);
    await storage.database.close();
    storage = ChainAgentStorage(session.path, 'postgres');
    final recovered = await storage.open(
      initial.copyWith(connectionString: '', authToken: null, refreshToken: null),
      'fixture-client',
    );
    expect(storage.resumed, isTrue);
    expect(storage.tokenId, tokenId);
    expect(storage.tokenValue == token, isTrue);
    expect(recovered.id, saved.id);
    expect(recovered.password == saved.password, isTrue);
    expect(recovered.authToken == saved.authToken, isTrue);
  }, skip: windowsDpapiRequired);
  test('missing vault refuses recovery without replacing the existing token or configuration', () async {
    await storage.open(initial, 'fixture-client');
    final boot = File('${session.path}/postgres-boot.json').readAsStringSync();
    await storage.database.close();
    File('${session.path}/vault/flutter_secure_storage.dat').deleteSync();
    storage = ChainAgentStorage(session.path, 'postgres');
    await expectLater(storage.open(initial, 'fixture-client'), throwsStateError);
    expect(File('${session.path}/postgres-boot.json').readAsStringSync(), boot);
    expect(await storage.database.select(storage.database.clientTokenCacheTable).get(), hasLength(1));
  }, skip: windowsDpapiRequired);
  test('corrupt native vault refuses recovery without plaintext fallback', () async {
    await storage.open(initial, 'fixture-client');
    await storage.database.close();
    File('${session.path}/vault/flutter_secure_storage.dat').writeAsBytesSync([1, 2, 3, 4], flush: true);
    storage = ChainAgentStorage(session.path, 'postgres');
    await expectLater(storage.open(initial, 'fixture-client'), throwsA(isA<Exception>()));
    expect(await storage.database.select(storage.database.configTable).get(), hasLength(1));
  }, skip: windowsDpapiRequired);
  test('missing ODBC secret refuses recovery even when bootstrap still contains the password', () async {
    await storage.open(initial, 'fixture-client');
    await storage.database.close();
    const vault = FlutterSecureStorage();
    await vault.delete(key: 'postgres_odbc_isolated-config_password');
    storage = ChainAgentStorage(session.path, 'postgres');
    await expectLater(storage.open(initial, 'fixture-client'), throwsStateError);
  }, skip: windowsDpapiRequired);
}

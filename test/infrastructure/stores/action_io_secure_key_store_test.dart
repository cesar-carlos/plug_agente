import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ActionIoSecureKeyStore store;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('action-io-key-test-');
    store = ActionIoSecureKeyStore(lockPath: '${directory.path}/key.lock');
  });
  tearDown(() => directory.delete(recursive: true));

  test('creates a random persisted key once and reloads existing ciphertext', () async {
    final first = (await store.load(journalIsEmpty: true)).getOrThrow();
    final ciphertext = (await first.encrypt([0, 255], context: [1, 2])).getOrThrow();
    final second = (await store.load(journalIsEmpty: false)).getOrThrow();
    expect(second.keyId, first.keyId);
    expect((await second.decrypt(ciphertext, expectedContext: [1, 2])).getOrThrow(), [0, 255]);
  });

  test('never creates a replacement key for a populated journal', () async {
    expect((await store.load(journalIsEmpty: false)).isError(), isTrue);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), isNull);
  });

  test('explicit fixture key does not read or replace the default namespace', () async {
    FlutterSecureStorage.setMockInitialValues({ActionIoSecureKeyStore.storageKey: 'untouched'});
    final isolated = ActionIoSecureKeyStore(
      lockPath: '${directory.path}/fixture.lock',
      keyName: 'fixture_action_io_unit',
    );
    final first = (await isolated.load(journalIsEmpty: true)).getOrThrow();
    final reopened = (await isolated.load(journalIsEmpty: false)).getOrThrow();
    expect(reopened.keyId, first.keyId);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), 'untouched');
    expect(await const FlutterSecureStorage().read(key: 'fixture_action_io_unit'), isNotNull);
  });

  test('corrupt key is preserved and refused even when the journal is empty', () async {
    FlutterSecureStorage.setMockInitialValues({ActionIoSecureKeyStore.storageKey: 'corrupted'});
    expect((await store.load(journalIsEmpty: true)).isError(), isTrue);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), 'corrupted');
  });
}

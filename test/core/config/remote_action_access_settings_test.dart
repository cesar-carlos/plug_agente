import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart';

class FailedPersistenceStore extends InMemoryAppSettingsStore {
  @override
  Object? get lastPersistError => Exception('Disk full');
}

void main() {
  test('ad-hoc requires explicit opt-in and survives unrelated preference changes', () async {
    final store = InMemoryAppSettingsStore();
    final flags = FeatureFlags(store);
    expect(flags.enableRemoteAdHocAgentActions, isFalse);
    expect((await flags.saveRemoteActionAccess(remote: true, io: false, adHoc: true)).isSuccess(), isTrue);
    expect(FeatureFlags(store).enableRemoteAdHocAgentActions, isTrue);
    await flags.saveRemoteActionAccess(remote: false, io: false);
    expect(flags.enableRemoteAdHocAgentActions, isTrue);
    await flags.saveRemoteActionAccess(remote: false, io: false, adHoc: false);
    expect(flags.enableRemoteAdHocAgentActions, isFalse);
    expect(flags.enableRemoteAgentActions, isFalse);
    expect(flags.enableClientTokenAuthorization, isTrue);
    expect(flags.enableElevatedAgentActions, isFalse);
    expect(flags.enableSqlOperations, isFalse);
  });

  test('failed ad-hoc opt-in is rolled back', () async {
    final flags = FeatureFlags(FailedPersistenceStore());
    final result = await flags.saveRemoteActionAccess(remote: true, io: false, adHoc: true);
    expect(result.exceptionOrNull(), isA<ConfigurationFailure>());
    expect(flags.enableRemoteAdHocAgentActions, isFalse);
  });

  test('opt-ins survive reopening the settings file', () async {
    final directory = await Directory.systemTemp.createTemp('remote-access-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/settings.json';
    final original = GlobalAppSettingsStore(filePath: path);
    await original.initialize();
    expect(
      (await FeatureFlags(original).saveRemoteActionAccess(remote: true, io: true, adHoc: true)).isSuccess(),
      isTrue,
    );
    final reopened = GlobalAppSettingsStore(filePath: path);
    await reopened.initialize();
    expect(FeatureFlags(reopened).enableRemoteAgentActions, isTrue);
    expect(FeatureFlags(reopened).enableActionIo, isTrue);
    expect(FeatureFlags(reopened).enableRemoteAdHocAgentActions, isTrue);
  });

  test('persists opt-ins without changing authorization or unrelated gates', () async {
    final store = InMemoryAppSettingsStore();
    final flags = FeatureFlags(store);
    expect(flags.enableRemoteAgentActions, isFalse);
    expect(flags.enableActionIo, isFalse);
    final result = await flags.saveRemoteActionAccess(remote: true, io: true);
    expect(result.isSuccess(), isTrue);
    expect(FeatureFlags(store).enableRemoteAgentActions, isTrue);
    expect(FeatureFlags(store).enableActionIo, isTrue);
    expect(store.getKeys(), {'feature_enable_remote_agent_actions', 'feature_enable_action_io'});
    expect(flags.enableRemoteAdHocAgentActions, isFalse);
    expect(flags.enableElevatedAgentActions, isFalse);
    expect(flags.enableSqlOperations, isFalse);
  });

  test('returns typed failure and restores disabled cache on persistence failure', () async {
    final flags = FeatureFlags(FailedPersistenceStore());
    final result = await flags.saveRemoteActionAccess(remote: true, io: true);
    expect(result.exceptionOrNull(), isA<ConfigurationFailure>());
    expect(flags.enableRemoteAgentActions, isFalse);
    expect(flags.enableActionIo, isFalse);
  });
}

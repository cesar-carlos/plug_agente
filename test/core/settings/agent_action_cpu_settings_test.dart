import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/settings/agent_action_cpu_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

class _Store extends Mock implements IAppSettingsStore {}

void main() {
  test('default preserves scheduling and saves an explicit limit', () async {
    final store = _Store();
    var value = 0;
    when(() => store.getInt(AgentActionCpuSettings.key)).thenAnswer((_) => value);
    when(() => store.setInt(AgentActionCpuSettings.key, 50)).thenAnswer((_) async {
      value = 50;
    });
    when(store.flushPendingPersistence).thenAnswer((_) async {});
    final settings = AgentActionCpuSettings(store);
    expect(settings.limitPercent, 0);
    expect((await settings.save(50)).isSuccess(), isTrue);
    expect(settings.limitPercent, 50);
  });
  test('rejects invalid limits without silently clamping them', () async {
    final store = _Store();
    final settings = AgentActionCpuSettings(store);
    expect((await settings.save(-1)).isError(), isTrue);
    expect((await settings.save(101)).isError(), isTrue);
    verifyNever(() => store.setInt(any(), any()));
  });
  test('reports deferred persistence failure', () async {
    final store = _Store();
    when(() => store.setInt(any(), any())).thenAnswer((_) async {});
    when(store.flushPendingPersistence).thenAnswer((_) async {});
    when(() => store.lastPersistError).thenReturn(StateError('disk full'));
    expect((await AgentActionCpuSettings(store).save(25)).isError(), isTrue);
  });
}

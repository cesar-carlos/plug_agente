import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/protocol/sql_operation_capability.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';

void main() {
  test('advertises only after explicit opt-in and a new negotiation snapshot', () async {
    final flags = FeatureFlags(
      InMemoryAppSettingsStore({
        'feature_enable_agent_actions': false,
        'feature_enable_remote_agent_actions': false,
      }),
    );
    final builder = TransportLocalCapabilitiesBuilder(featureFlags: flags);
    expect(builder.build().extensions.containsKey(SqlOperationCapability.key), isFalse);
    await flags.setEnableSqlOperations(true);
    builder.invalidateCache();
    expect(builder.build().extensions[SqlOperationCapability.key], SqlOperationCapability.advertisement);
    await flags.setEnableSqlOperations(false);
    builder.invalidateCache();
    expect(builder.build().extensions.containsKey(SqlOperationCapability.key), isFalse);
  });
}

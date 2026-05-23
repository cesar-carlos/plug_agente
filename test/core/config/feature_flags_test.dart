import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('FeatureFlags', () {
    test('keeps binary payload enabled even with legacy disabled preference', () async {
      final store = InMemoryAppSettingsStore({
        'feature_enable_binary_payload': false,
      });
      final flags = FeatureFlags(store);

      expect(flags.enableBinaryPayload, isTrue);

      await flags.setEnableBinaryPayload(false);

      expect(flags.enableBinaryPayload, isTrue);
      expect(store.getBool('feature_enable_binary_payload'), isTrue);
    });

    test('keeps incoming payload signatures optional by default', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);

      expect(flags.enablePayloadSigning, isFalse);
      expect(flags.requireIncomingPayloadSignatures, isFalse);

      await flags.setEnablePayloadSigning(true);

      expect(flags.enablePayloadSigning, isTrue);
      expect(flags.requireIncomingPayloadSignatures, isFalse);
    });

    test('uses balanced compression defaults for transport performance', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      expect(flags.outboundCompressionMode, OutboundCompressionMode.auto);
      expect(flags.enableCompression, isTrue);
      expect(flags.compressionThreshold, 4096);
    });

    test('enables adaptive ODBC pooling by default with persisted opt-out', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isTrue);

      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(false);

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isFalse);
      expect(store.getBool('feature_enable_odbc_experimental_driver_adaptive_pooling'), isFalse);
    });

    test('resets adaptive ODBC pooling to enabled default', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(false);

      await flags.resetToDefaults();

      expect(flags.enableOdbcExperimentalDriverAdaptivePooling, isTrue);
    });

    test('enables DB streaming path by default when socket chunking is enabled separately', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      expect(flags.enableSocketStreamingFromDb, isTrue);
      expect(flags.enableSocketStreamingChunks, isFalse);
    });

    test('uses conservative defaults for agent action rollout flags', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      expect(flags.enableAgentActions, isTrue);
      expect(flags.enableRemoteAgentActions, isFalse);
      expect(flags.enableRemoteAdHocAgentActions, isFalse);
      expect(flags.enableElevatedAgentActions, isFalse);
      expect(flags.enableAgentActionRemoteAudit, isTrue);
      expect(flags.enableAgentActionsMaintenanceMode, isFalse);
      expect(flags.enableAgentActionDangerousCommandWarnMode, isFalse);

      await flags.setEnableAgentActions(false);
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableRemoteAdHocAgentActions(true);
      await flags.setEnableElevatedAgentActions(true);
      await flags.setEnableAgentActionsMaintenanceMode(true);

      expect(flags.enableAgentActions, isFalse);
      expect(flags.enableRemoteAgentActions, isTrue);
      expect(flags.enableRemoteAdHocAgentActions, isTrue);
      expect(flags.enableElevatedAgentActions, isTrue);
      expect(flags.enableAgentActionsMaintenanceMode, isTrue);

      await flags.resetToDefaults();

      expect(flags.enableAgentActions, isTrue);
      expect(flags.enableRemoteAgentActions, isFalse);
      expect(flags.enableRemoteAdHocAgentActions, isFalse);
      expect(flags.enableElevatedAgentActions, isFalse);
      expect(flags.enableAgentActionRemoteAudit, isTrue);
      expect(flags.enableAgentActionsMaintenanceMode, isFalse);
      expect(flags.enableAgentActionDangerousCommandWarnMode, isFalse);
    });

    test('disableAgentActionsRemoteRollout should turn off remote ad-hoc and elevated only', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());

      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableRemoteAdHocAgentActions(true);
      await flags.setEnableElevatedAgentActions(true);

      await flags.disableAgentActionsRemoteRollout();

      expect(flags.enableAgentActions, isTrue);
      expect(flags.enableRemoteAgentActions, isFalse);
      expect(flags.enableRemoteAdHocAgentActions, isFalse);
      expect(flags.enableElevatedAgentActions, isFalse);
      expect(flags.enableAgentActionRemoteAudit, isTrue);
    });

    test('keeps parallel JSON-RPC batch dispatch disabled by default', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);

      expect(flags.enableParallelJsonRpcBatchDispatch, isFalse);

      await flags.setEnableParallelJsonRpcBatchDispatch(true);

      expect(flags.enableParallelJsonRpcBatchDispatch, isTrue);
      expect(store.getBool('feature_enable_parallel_json_rpc_batch_dispatch'), isTrue);

      await flags.resetToDefaults();

      expect(flags.enableParallelJsonRpcBatchDispatch, isFalse);
    });
  });
}

import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';

class RuntimeSupportDiagnosticsBuilder {
  const RuntimeSupportDiagnosticsBuilder();

  SupportDiagnosticsSection buildSection({
    required RuntimeCapabilities capabilities,
    RuntimeDetectionDiagnostics? diagnostics,
    String title = 'Runtime Detection',
  }) {
    final fields = <SupportDiagnosticsField>[
      SupportDiagnosticsField(
        key: 'runtime_mode',
        value: capabilities.mode.name,
      ),
      SupportDiagnosticsField(
        key: 'supports_tray',
        value: capabilities.supportsTray,
      ),
      SupportDiagnosticsField(
        key: 'supports_notifications',
        value: capabilities.supportsNotifications,
      ),
      SupportDiagnosticsField(
        key: 'supports_auto_update',
        value: capabilities.supportsAutoUpdate,
      ),
      SupportDiagnosticsField(
        key: 'supports_window_manager',
        value: capabilities.supportsWindowManager,
      ),
      SupportDiagnosticsField(
        key: 'degradation_reasons',
        value: capabilities.degradationReasons.isEmpty ? null : capabilities.degradationReasons.join(' | '),
      ),
    ];

    if (diagnostics == null) {
      fields.add(
        const SupportDiagnosticsField(
          key: 'detection_source',
          value: 'unavailable',
        ),
      );
      return SupportDiagnosticsSection(
        title: title,
        fields: fields,
      );
    }

    fields.addAll(<SupportDiagnosticsField>[
      SupportDiagnosticsField(
        key: 'detection_source',
        value: diagnostics.sourceName,
      ),
      SupportDiagnosticsField(
        key: 'version',
        value: diagnostics.versionInfo?.versionString,
      ),
      SupportDiagnosticsField(
        key: 'is_server',
        value: diagnostics.versionInfo?.isServer,
      ),
      SupportDiagnosticsField(
        key: 'product_name',
        value: diagnostics.versionInfo?.productName,
      ),
      SupportDiagnosticsField(
        key: 'raw_os_version',
        value: diagnostics.rawOperatingSystemVersion,
      ),
      SupportDiagnosticsField(
        key: 'detection_failure',
        value: diagnostics.failureMessage,
      ),
    ]);

    return SupportDiagnosticsSection(
      title: title,
      fields: fields,
    );
  }
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/support/runtime_support_diagnostics_builder.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsRuntimeSupportCard extends StatelessWidget {
  const AgentActionsRuntimeSupportCard({
    required this.capabilities,
    required this.diagnostics,
    super.key,
  });

  static const RuntimeSupportDiagnosticsBuilder _builder = RuntimeSupportDiagnosticsBuilder();

  final RuntimeCapabilities capabilities;
  final RuntimeDetectionDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    if (!_shouldShowCard()) {
      return const SizedBox.shrink();
    }

    final section = _builder.buildSection(
      capabilities: capabilities,
      diagnostics: diagnostics,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: context.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _CapabilityPill(
                label: 'runtime_mode',
                value: capabilities.mode.name,
              ),
              _CapabilityPill(
                label: 'tray',
                value: capabilities.supportsTray ? 'on' : 'off',
              ),
              _CapabilityPill(
                label: 'notifications',
                value: capabilities.supportsNotifications ? 'on' : 'off',
              ),
              _CapabilityPill(
                label: 'auto_update',
                value: capabilities.supportsAutoUpdate ? 'on' : 'off',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: section.fields
                .map(
                  (field) => _RuntimeSupportLine(field: field),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  bool _shouldShowCard() {
    if (capabilities.isDegraded || capabilities.isUnsupported) {
      return true;
    }

    return diagnostics?.source == RuntimeDetectionSource.detectionFailed;
  }
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: context.captionText,
      ),
    );
  }
}

class _RuntimeSupportLine extends StatelessWidget {
  const _RuntimeSupportLine({
    required this.field,
  });

  final SupportDiagnosticsField field;

  @override
  Widget build(BuildContext context) {
    final fieldValue = field.value;
    final value = fieldValue == null || (fieldValue is String && fieldValue.trim().isEmpty)
        ? '-'
        : fieldValue.toString();

    return SizedBox(
      width: 280,
      child: SelectableText.rich(
        TextSpan(
          style: context.captionText,
          children: [
            TextSpan(text: '${field.key}: '),
            TextSpan(
              text: value,
              style: context.captionText.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

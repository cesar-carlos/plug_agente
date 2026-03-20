import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

/// Advanced diagnostics toggles (may log sensitive SQL). Requires dependency
/// injection setup so the service locator is ready.
class DiagnosticsConfigSection extends StatefulWidget {
  const DiagnosticsConfigSection({super.key});

  @override
  State<DiagnosticsConfigSection> createState() => _DiagnosticsConfigSectionState();
}

class _DiagnosticsConfigSectionState extends State<DiagnosticsConfigSection> {
  late final FeatureFlags _flags = getIt<FeatureFlags>();
  late bool _odbcPaginatedSqlLog;

  @override
  void initState() {
    super.initState();
    _odbcPaginatedSqlLog = _flags.enableOdbcPaginatedSqlDebugLog;
  }

  Future<void> _setOdbcPaginatedSqlLog(bool value) async {
    setState(() => _odbcPaginatedSqlLog = value);
    await _flags.setEnableOdbcPaginatedSqlDebugLog(value);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SettingsSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsSectionTitle(
                    title: AppStrings.diagnosticsSectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const InfoBar(
                    title: Text(AppStrings.diagnosticsWarningTitle),
                    content: Text(AppStrings.diagnosticsWarningBody),
                    severity: InfoBarSeverity.warning,
                    isLong: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsToggleTile(
                    label: AppStrings.diagnosticsOdbcPaginatedSqlLogLabel,
                    value: _odbcPaginatedSqlLog,
                    onChanged: _setOdbcPaginatedSqlLog,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.diagnosticsOdbcPaginatedSqlLogDescription,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

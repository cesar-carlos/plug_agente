import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _odbcPaginatedSqlLog = _flags.enableOdbcPaginatedSqlDebugLog;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    final l10n = AppLocalizations.of(context)!;
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SettingsSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSectionTitle(
                    title: l10n.diagnosticsSectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  InfoBar(
                    title: Text(l10n.diagnosticsWarningTitle),
                    content: Text(l10n.diagnosticsWarningBody),
                    severity: InfoBarSeverity.warning,
                    isLong: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsToggleTile(
                    label: l10n.diagnosticsOdbcPaginatedSqlLogLabel,
                    value: _odbcPaginatedSqlLog,
                    onChanged: (bool value) {
                      unawaited(_setOdbcPaginatedSqlLog(value));
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.diagnosticsOdbcPaginatedSqlLogDescription,
                    style: context.captionText,
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

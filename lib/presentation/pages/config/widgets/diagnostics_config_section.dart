import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

/// Advanced diagnostics toggles (may log sensitive SQL). Requires dependency
/// injection setup so the service locator is ready.
class DiagnosticsConfigSection extends StatefulWidget {
  const DiagnosticsConfigSection({super.key});

  @override
  State<DiagnosticsConfigSection> createState() =>
      _DiagnosticsConfigSectionState();
}

class _DiagnosticsConfigSectionState extends State<DiagnosticsConfigSection> {
  late final FeatureFlags _flags = getIt<FeatureFlags>();
  late bool _odbcPaginatedSqlLog;
  late bool _socketOutboundCompressionDebugLog;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _odbcPaginatedSqlLog = _flags.enableOdbcPaginatedSqlDebugLog;
    _socketOutboundCompressionDebugLog =
        _flags.enableSocketOutboundCompressionDebugLog;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final odbcLog = _flags.enableOdbcPaginatedSqlDebugLog;
    final socketCmpLog = _flags.enableSocketOutboundCompressionDebugLog;
    if (odbcLog != _odbcPaginatedSqlLog ||
        socketCmpLog != _socketOutboundCompressionDebugLog) {
      setState(() {
        _odbcPaginatedSqlLog = odbcLog;
        _socketOutboundCompressionDebugLog = socketCmpLog;
      });
    }
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

  Future<void> _setSocketOutboundCompressionDebugLog(bool value) async {
    setState(() => _socketOutboundCompressionDebugLog = value);
    await _flags.setEnableSocketOutboundCompressionDebugLog(value);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    onChanged: (bool value) {
                      unawaited(
                        _setOdbcPaginatedSqlLog(value).catchError(
                          (Object e, StackTrace stackTrace) {
                            AppLogger.warning(
                              'Failed to update ODBC paginated SQL log flag',
                              e,
                              stackTrace,
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.diagnosticsOdbcPaginatedSqlLogDescription,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsToggleTile(
                    label:
                        AppStrings.diagnosticsSocketOutboundCompressionDebugLogLabel,
                    value: _socketOutboundCompressionDebugLog,
                    onChanged: (bool value) {
                      unawaited(
                        _setSocketOutboundCompressionDebugLog(value).catchError(
                          (Object e, StackTrace stackTrace) {
                            AppLogger.warning(
                              'Failed to update socket outbound compression '
                              'debug log flag',
                              e,
                              stackTrace,
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings
                        .diagnosticsSocketOutboundCompressionDebugLogDescription,
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

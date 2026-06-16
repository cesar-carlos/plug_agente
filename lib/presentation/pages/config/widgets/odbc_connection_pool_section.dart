import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/use_cases/reload_odbc_runtime_dependencies.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/numeric_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class OdbcConnectionPoolSection extends StatefulWidget {
  const OdbcConnectionPoolSection({
    super.key,
    ReloadOdbcRuntimeDependencies? reloadOdbcRuntime,
  }) : _reloadOdbcRuntime = reloadOdbcRuntime;

  final ReloadOdbcRuntimeDependencies? _reloadOdbcRuntime;

  @override
  State<OdbcConnectionPoolSection> createState() => _OdbcConnectionPoolSectionState();
}

class _OdbcConnectionPoolSectionState extends State<OdbcConnectionPoolSection> {
  late final TextEditingController _poolSizeController;
  late final TextEditingController _loginTimeoutController;
  late final TextEditingController _maxResultBufferController;
  late final TextEditingController _streamingChunkSizeController;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  Map<String, Object?>? _poolDiagnostics;

  @override
  void initState() {
    super.initState();
    _poolSizeController = TextEditingController();
    _loginTimeoutController = TextEditingController();
    _maxResultBufferController = TextEditingController();
    _streamingChunkSizeController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final settings = context.read<IOdbcConnectionSettings>();
    try {
      await settings.load();
    } on Object catch (error, stackTrace) {
      AppLogger.error('Failed to load advanced ODBC settings', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = AppLocalizations.of(context)!.odbcErrorLoadFailed;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _poolSizeController.text = settings.poolSize.toString();
      _loginTimeoutController.text = settings.loginTimeoutSeconds.toString();
      _maxResultBufferController.text = settings.maxResultBufferMb.toString();
      _streamingChunkSizeController.text = settings.streamingChunkSizeKb.toString();
      _isLoading = false;
    });
    final pool = context.read<IConnectionPool>();
    final healthResult = await pool.healthCheckAll();
    healthResult.fold(
      (_) => AppLogger.info('Connection pool health check passed'),
      (failure) => AppLogger.warning(
        'Connection pool health check: $failure',
      ),
    );
    final diagnostics = switch (pool) {
      final IConnectionPoolDiagnostics diagnosticsPool => diagnosticsPool.getHealthDiagnostics(),
      _ => null,
    };
    if (!mounted) return;
    setState(() => _poolDiagnostics = diagnostics);
  }

  Future<void> _saveSettings() async {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final poolSize = int.tryParse(_poolSizeController.text);
    final loginTimeout = int.tryParse(_loginTimeoutController.text);
    final maxResultBuffer = int.tryParse(_maxResultBufferController.text);
    final streamingChunkSize = int.tryParse(_streamingChunkSizeController.text);

    if (poolSize == null || poolSize < 1 || poolSize > 20) {
      _showError(l10n.odbcErrorPoolRange);
      return;
    }
    if (loginTimeout == null || loginTimeout < 1 || loginTimeout > 120) {
      _showError(l10n.odbcErrorLoginTimeoutRange);
      return;
    }
    if (maxResultBuffer == null ||
        maxResultBuffer < ConnectionConstants.minMaxResultBufferMb ||
        maxResultBuffer > ConnectionConstants.maxMaxResultBufferMb) {
      _showError(l10n.odbcErrorBufferRange);
      return;
    }
    if (streamingChunkSize == null || streamingChunkSize < 64 || streamingChunkSize > 8192) {
      _showError(l10n.odbcErrorChunkRange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = context.read<IOdbcConnectionSettings>();
      final reloadOdbcRuntime =
          widget._reloadOdbcRuntime ?? context.read<ReloadOdbcRuntimeDependencies>();
      await settings.setPoolSize(poolSize);
      await settings.setLoginTimeoutSeconds(loginTimeout);
      await settings.setMaxResultBufferMb(maxResultBuffer);
      await settings.setStreamingChunkSizeKb(streamingChunkSize);
      final settingsAppliedNow = await reloadOdbcRuntime();

      if (!mounted) return;
      _showSuccess(settingsAppliedNow);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to save advanced ODBC settings',
        error,
        stackTrace,
      );
      if (mounted) {
        _showError(AppLocalizations.of(context)!.odbcErrorSaveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _restoreDefaults() async {
    _poolSizeController.text = ConnectionConstants.defaultPoolSize.toString();
    _loginTimeoutController.text = ConnectionConstants.defaultLoginTimeout.inSeconds.toString();
    _maxResultBufferController.text = (ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024)).toString();
    _streamingChunkSizeController.text = ConnectionConstants.defaultStreamingChunkSizeKb.toString();

    await _saveSettings();
  }

  void _showError(String message) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleError,
      message: message,
    );
  }

  List<String> _poolDiagnosticsLines(AppLocalizations l10n) {
    final diagnostics = _poolDiagnostics;
    if (diagnostics == null) {
      return const [];
    }

    final lines = <String>[
      l10n.odbcTextPoolEffectiveStrategy(
        _formatEffectiveStrategy(diagnostics['effective_strategy']),
      ),
    ];

    final experimentalEnabled = diagnostics['experimental_enabled'];
    if (experimentalEnabled is bool) {
      lines.add(
        experimentalEnabled ? l10n.odbcTextPoolAdaptiveModeEnabled : l10n.odbcTextPoolAdaptiveModeDisabled,
      );
    }

    final nativeEligible = diagnostics['native_eligible'];
    if (nativeEligible is bool) {
      lines.add(
        nativeEligible ? l10n.odbcTextPoolNativeEligibleYes : l10n.odbcTextPoolNativeEligibleNo,
      );
    }

    if (diagnostics['native_circuit_open'] == true) {
      lines.add(l10n.odbcTextPoolNativeCircuitOpen);
    }

    final skipReason = diagnostics['native_skip_reason'];
    if (skipReason is String && skipReason.isNotEmpty) {
      lines.add(l10n.odbcTextPoolNativeSkipReason(skipReason));
    }

    return lines;
  }

  String _formatEffectiveStrategy(Object? strategy) {
    return switch (strategy) {
      'native' => 'native',
      'native_compatible' => 'native_compatible',
      'lease' => 'lease',
      final String value => value,
      _ => 'lease',
    };
  }

  void _showSuccess(bool settingsAppliedNow) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final message = settingsAppliedNow ? l10n.odbcSuccessAppliedNow : l10n.odbcSuccessAppliedGradually;

    SettingsFeedback.showSuccess(
      context: context,
      title: l10n.odbcModalTitleSaved,
      message: message,
    );
  }

  @override
  void dispose() {
    _poolSizeController.dispose();
    _loginTimeoutController.dispose();
    _maxResultBufferController.dispose();
    _streamingChunkSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: ProgressRing());
    }

    final l10n = AppLocalizations.of(context)!;

    if (_loadError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxFormWidth),
          child: InlineFeedbackCard(
            severity: InfoBarSeverity.error,
            title: l10n.modalTitleError,
            message: _loadError,
            content: Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: l10n.btnRetry,
                onPressed: _loadSettings,
              ),
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSectionBlock(
                title: l10n.odbcSectionTitle,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.odbcBlockPool,
                        style: context.bodyStrong,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcBlockPoolDescription,
                        style: context.bodyText,
                      ),
                      const SizedBox(height: 16),
                      NumericField(
                        label: l10n.odbcFieldPoolSize,
                        controller: _poolSizeController,
                        hint: l10n.odbcHintPoolSize,
                        minValue: 1,
                        maxValue: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextPoolSizeLimiterHelp,
                        style: context.captionText,
                      ),
                      if (_poolDiagnostics != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          l10n.odbcTextPoolRuntimeDiagnosticsTitle,
                          style: context.captionStrong,
                        ),
                        const SizedBox(height: 4),
                        for (final line in _poolDiagnosticsLines(l10n))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              line,
                              style: context.captionText,
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n.odbcBlockTimeouts,
                        style: context.bodyStrong,
                      ),
                      const SizedBox(height: 8),
                      NumericField(
                        label: l10n.odbcFieldLoginTimeout,
                        controller: _loginTimeoutController,
                        hint: l10n.odbcHintLoginTimeout,
                        minValue: 1,
                        maxValue: 120,
                      ),
                      const SizedBox(height: 16),
                      NumericField(
                        label: l10n.odbcFieldResultBuffer,
                        controller: _maxResultBufferController,
                        hint: l10n.odbcHintResultBuffer,
                        minValue: ConnectionConstants.minMaxResultBufferMb,
                        maxValue: ConnectionConstants.maxMaxResultBufferMb,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextResultBufferHelp,
                        style: context.captionText,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.odbcBlockStreaming,
                        style: context.bodyStrong,
                      ),
                      const SizedBox(height: 8),
                      NumericField(
                        label: l10n.odbcFieldChunkSize,
                        controller: _streamingChunkSizeController,
                        hint: l10n.odbcHintChunkSize,
                        minValue: 64,
                        maxValue: 8192,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextStreamingHelp,
                        style: context.captionText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextQuickRecommendation,
                        style: context.captionStrong,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.odbcTextQuickRecommendationItems,
                        style: context.captionText,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.odbcTextChunkWarning,
                        style: context.captionText,
                      ),
                      const SizedBox(height: 24),
                      SettingsActionRow(
                        spacing: 12,
                        leading: AppButton(
                          label: l10n.odbcButtonRestoreDefault,
                          isPrimary: false,
                          onPressed: _isSaving ? null : _restoreDefaults,
                        ),
                        trailing: AppButton(
                          label: l10n.odbcButtonSaveAdvanced,
                          isLoading: _isSaving,
                          onPressed: _saveSettings,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

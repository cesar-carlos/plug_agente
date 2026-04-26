import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/numeric_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class OdbcConnectionPoolSection extends StatefulWidget {
  const OdbcConnectionPoolSection({super.key});

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
  bool _useNativeOdbcPool = false;
  bool _useNativeOdbcPoolAtLoad = false;
  bool _nativePoolTestOnCheckout = true;

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
    final settings = getIt<IOdbcConnectionSettings>();
    await settings.load();
    if (!mounted) return;
    setState(() {
      _poolSizeController.text = settings.poolSize.toString();
      _loginTimeoutController.text = settings.loginTimeoutSeconds.toString();
      _maxResultBufferController.text = settings.maxResultBufferMb.toString();
      _streamingChunkSizeController.text = settings.streamingChunkSizeKb.toString();
      _useNativeOdbcPool = settings.useNativeOdbcPool;
      _useNativeOdbcPoolAtLoad = settings.useNativeOdbcPool;
      _nativePoolTestOnCheckout = settings.nativePoolTestOnCheckout;
      _isLoading = false;
    });
    final healthResult = await getIt<IConnectionPool>().healthCheckAll();
    healthResult.fold(
      (_) => AppLogger.info('Connection pool health check passed'),
      (failure) => AppLogger.warning(
        'Connection pool health check: $failure',
      ),
    );
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
    if (maxResultBuffer == null || maxResultBuffer < 8 || maxResultBuffer > 128) {
      _showError(l10n.odbcErrorBufferRange);
      return;
    }
    if (streamingChunkSize == null || streamingChunkSize < 64 || streamingChunkSize > 8192) {
      _showError(l10n.odbcErrorChunkRange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = getIt<IOdbcConnectionSettings>();
      final poolModeChanged = _useNativeOdbcPool != _useNativeOdbcPoolAtLoad;
      await settings.setPoolSize(poolSize);
      await settings.setLoginTimeoutSeconds(loginTimeout);
      await settings.setMaxResultBufferMb(maxResultBuffer);
      await settings.setStreamingChunkSizeKb(streamingChunkSize);
      await settings.setUseNativeOdbcPool(_useNativeOdbcPool);
      await settings.setNativePoolTestOnCheckout(_nativePoolTestOnCheckout);

      final settingsAppliedNow = await reloadOdbcRuntimeDependencies();

      if (!mounted) return;
      _showSuccess(
        settingsAppliedNow,
        poolModeChanged: poolModeChanged,
      );
      if (poolModeChanged) {
        setState(() => _useNativeOdbcPoolAtLoad = _useNativeOdbcPool);
      }
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
    setState(() => _useNativeOdbcPool = false);
    _nativePoolTestOnCheckout = true;
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

  void _showSuccess(
    bool settingsAppliedNow, {
    required bool poolModeChanged,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final base = settingsAppliedNow ? l10n.odbcSuccessAppliedNow : l10n.odbcSuccessAppliedGradually;
    final message = poolModeChanged ? '$base${l10n.odbcSuccessPoolModeRestartAppend}' : base;

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
                      const SizedBox(height: 16),
                      SettingsToggleTile(
                        label: l10n.odbcFieldNativePool,
                        value: _useNativeOdbcPool,
                        onChanged: _isSaving
                            ? null
                            : (bool value) {
                                setState(() => _useNativeOdbcPool = value);
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextNativePoolHelp,
                        style: context.captionText,
                      ),
                      const SizedBox(height: 16),
                      SettingsToggleTile(
                        label: l10n.odbcFieldNativePoolCheckoutValidation,
                        value: _nativePoolTestOnCheckout,
                        onChanged: !_useNativeOdbcPool || _isSaving
                            ? null
                            : (bool value) {
                                setState(() => _nativePoolTestOnCheckout = value);
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.odbcTextNativePoolCheckoutValidationHelp,
                        style: context.captionText,
                      ),
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
                        minValue: 8,
                        maxValue: 128,
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

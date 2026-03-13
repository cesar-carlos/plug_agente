import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/actions/settings_action_row.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/numeric_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class OdbcConnectionPoolSection extends StatefulWidget {
  const OdbcConnectionPoolSection({super.key});

  @override
  State<OdbcConnectionPoolSection> createState() =>
      _OdbcConnectionPoolSectionState();
}

class _OdbcConnectionPoolSectionState extends State<OdbcConnectionPoolSection> {
  late final TextEditingController _poolSizeController;
  late final TextEditingController _loginTimeoutController;
  late final TextEditingController _maxResultBufferController;
  late final TextEditingController _streamingChunkSizeController;
  bool _isLoading = true;
  bool _isSaving = false;

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
      _streamingChunkSizeController.text = settings.streamingChunkSizeKb
          .toString();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final poolSize = int.tryParse(_poolSizeController.text);
    final loginTimeout = int.tryParse(_loginTimeoutController.text);
    final maxResultBuffer = int.tryParse(_maxResultBufferController.text);
    final streamingChunkSize = int.tryParse(_streamingChunkSizeController.text);

    if (poolSize == null || poolSize < 1 || poolSize > 20) {
      _showError(AppStrings.odbcErrorPoolRange);
      return;
    }
    if (loginTimeout == null || loginTimeout < 1 || loginTimeout > 120) {
      _showError(AppStrings.odbcErrorLoginTimeoutRange);
      return;
    }
    if (maxResultBuffer == null ||
        maxResultBuffer < 8 ||
        maxResultBuffer > 128) {
      _showError(AppStrings.odbcErrorBufferRange);
      return;
    }
    if (streamingChunkSize == null ||
        streamingChunkSize < 64 ||
        streamingChunkSize > 8192) {
      _showError(AppStrings.odbcErrorChunkRange);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = getIt<IOdbcConnectionSettings>();
      await settings.setPoolSize(poolSize);
      await settings.setLoginTimeoutSeconds(loginTimeout);
      await settings.setMaxResultBufferMb(maxResultBuffer);
      await settings.setStreamingChunkSizeKb(streamingChunkSize);

      final closeResult = await getIt<IConnectionPool>().closeAll();
      final settingsAppliedNow = closeResult.isSuccess();

      if (!mounted) return;
      _showSuccess(settingsAppliedNow);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Failed to save advanced ODBC settings',
        error,
        stackTrace,
      );
      _showError(AppStrings.odbcErrorSaveFailed);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _restoreDefaults() async {
    _poolSizeController.text = ConnectionConstants.defaultPoolSize.toString();
    _loginTimeoutController.text = ConnectionConstants
        .defaultLoginTimeout
        .inSeconds
        .toString();
    _maxResultBufferController.text =
        (ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024))
            .toString();
    _streamingChunkSizeController.text = ConnectionConstants
        .defaultStreamingChunkSizeKb
        .toString();

    await _saveSettings();
  }

  void _showError(String message) {
    if (!mounted) return;
    SettingsFeedback.showError(
      context: context,
      title: AppStrings.modalTitleError,
      message: message,
    );
  }

  void _showSuccess(bool settingsAppliedNow) {
    if (!mounted) return;
    final message = settingsAppliedNow
        ? AppStrings.odbcSuccessAppliedNow
        : AppStrings.odbcSuccessAppliedGradually;

    SettingsFeedback.showSuccess(
      context: context,
      title: AppStrings.odbcModalTitleSaved,
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

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSectionBlock(
              title: AppStrings.odbcSectionTitle,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                    AppStrings.odbcBlockPool,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.odbcBlockPoolDescription,
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 16),
                  NumericField(
                    label: AppStrings.odbcFieldPoolSize,
                    controller: _poolSizeController,
                    hint: AppStrings.odbcHintPoolSize,
                    minValue: 1,
                    maxValue: 20,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.odbcBlockTimeouts,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  NumericField(
                    label: AppStrings.odbcFieldLoginTimeout,
                    controller: _loginTimeoutController,
                    hint: AppStrings.odbcHintLoginTimeout,
                    minValue: 1,
                    maxValue: 120,
                  ),
                  const SizedBox(height: 16),
                  NumericField(
                    label: AppStrings.odbcFieldResultBuffer,
                    controller: _maxResultBufferController,
                    hint: AppStrings.odbcHintResultBuffer,
                    minValue: 8,
                    maxValue: 128,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.odbcTextResultBufferHelp,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.odbcBlockStreaming,
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  NumericField(
                    label: AppStrings.odbcFieldChunkSize,
                    controller: _streamingChunkSizeController,
                    hint: AppStrings.odbcHintChunkSize,
                    minValue: 64,
                    maxValue: 8192,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.odbcTextStreamingHelp,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.odbcTextQuickRecommendation,
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.odbcTextQuickRecommendationItems,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.odbcTextChunkWarning,
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 24),
                  SettingsActionRow(
                    spacing: 12,
                    leading: AppButton(
                      label: AppStrings.odbcButtonRestoreDefault,
                      isPrimary: false,
                      onPressed: _isSaving ? null : _restoreDefaults,
                    ),
                    trailing: AppButton(
                      label: AppStrings.odbcButtonSaveAdvanced,
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

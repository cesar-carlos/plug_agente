import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

/// Listens to [ConfigProvider] error transitions and surfaces a modal when
/// a new error appears, clearing it through the provider on confirm.
class ConfigErrorFeedback extends StatefulWidget {
  const ConfigErrorFeedback({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<ConfigErrorFeedback> createState() => _ConfigErrorFeedbackState();
}

class _ConfigErrorFeedbackState extends State<ConfigErrorFeedback> {
  String _previousError = '';
  ConfigProvider? _configProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _configProvider = context.read<ConfigProvider>()..addListener(_onConfigChanged);
      _previousError = _configProvider!.error;
    });
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (!mounted) {
      return;
    }

    final currentError = context.read<ConfigProvider>().error;
    if (currentError.isNotEmpty && currentError != _previousError) {
      _showErrorModal(currentError);
    }
    _previousError = currentError;
  }

  void _showErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleConfigError,
      message: error,
      onConfirm: () => context.read<ConfigProvider>().clearError(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

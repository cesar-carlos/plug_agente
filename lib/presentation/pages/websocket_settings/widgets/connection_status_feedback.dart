import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

/// Listens to [ConnectionProvider] transitions for the current config and
/// surfaces "connected" success modals plus connection error feedback.
class ConnectionStatusFeedback extends StatefulWidget {
  const ConnectionStatusFeedback({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<ConnectionStatusFeedback> createState() => _ConnectionStatusFeedbackState();
}

class _ConnectionStatusFeedbackState extends State<ConnectionStatusFeedback> {
  ConnectionStatus? _previousStatus;
  String _previousError = '';
  ConnectionProvider? _connectionProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _connectionProvider = context.read<ConnectionProvider>()..addListener(_onConnectionChanged);
      _previousStatus = _connectionProvider!.status;
      _previousError = _connectionProvider!.error;
    });
  }

  @override
  void dispose() {
    _connectionProvider?.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) {
      return;
    }

    final connectionProvider = context.read<ConnectionProvider>();
    final currentConfigId = context.read<ConfigProvider>().currentConfig?.id;
    final currentStatus = connectionProvider.status;
    final currentError = connectionProvider.error;
    final isCurrentPageConfig = connectionProvider.activeConfigId == currentConfigId;

    if (isCurrentPageConfig &&
        _previousStatus != ConnectionStatus.connected &&
        currentStatus == ConnectionStatus.connected) {
      _showSuccessModal();
    }

    if (isCurrentPageConfig && currentError.isNotEmpty && currentError != _previousError) {
      _showErrorModal(currentError);
    }

    _previousStatus = currentStatus;
    _previousError = currentError;
  }

  void _showSuccessModal() {
    final l10n = AppLocalizations.of(context)!;
    SettingsFeedback.showSuccess(
      context: context,
      title: l10n.modalTitleConnectionEstablished,
      message: l10n.msgWebSocketConnectedSuccessfully,
    );
  }

  void _showErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleConnectionError,
      message: error,
      onConfirm: () => context.read<ConnectionProvider>().clearError(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

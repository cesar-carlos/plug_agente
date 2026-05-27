import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

/// Listens to [AuthProvider] transitions for the currently selected config
/// and surfaces success/error modals when status or error actually change.
///
/// Encapsulates the previous-state tracking that the parent page used to
/// own, so the page itself stops being a side-effect hub for auth events.
class AuthStatusFeedback extends StatefulWidget {
  const AuthStatusFeedback({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<AuthStatusFeedback> createState() => _AuthStatusFeedbackState();
}

class _AuthStatusFeedbackState extends State<AuthStatusFeedback> {
  AuthStatus? _previousStatus;
  String _previousError = '';
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _authProvider = context.read<AuthProvider>()..addListener(_onAuthChanged);
      _previousStatus = _authProvider!.status;
      _previousError = _authProvider!.error;
    });
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentConfigId = context.read<ConfigProvider>().currentConfig?.id;
    final currentStatus = authProvider.status;
    final currentError = authProvider.error;
    final isCurrentPageConfig = authProvider.activeConfigId == currentConfigId;

    if (isCurrentPageConfig &&
        _previousStatus != AuthStatus.authenticated &&
        currentStatus == AuthStatus.authenticated &&
        currentError.isEmpty) {
      if (!authProvider.pullSuppressAuthSuccessModalOnce()) {
        _showSuccessModal();
      }
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
      title: l10n.modalTitleSuccess,
      message: l10n.msgAuthenticatedSuccessfully,
    );
  }

  void _showErrorModal(String error) {
    final l10n = AppLocalizations.of(context)!;
    SettingsFeedback.showError(
      context: context,
      title: l10n.modalTitleAuthError,
      message: error,
      onConfirm: () => context.read<AuthProvider>().clearError(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

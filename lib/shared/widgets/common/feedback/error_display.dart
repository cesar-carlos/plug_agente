import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';

class ErrorDisplay extends StatelessWidget {
  const ErrorDisplay({
    required this.error,
    this.title,
    this.onRetry,
    super.key,
  });

  final Object error;
  final String? title;
  final VoidCallback? onRetry;

  static Future<void> showModal(
    BuildContext context, {
    required Object error,
    String? title,
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final display = ErrorDisplay(
      error: error,
      title: title,
      onRetry: onRetry,
    );

    return MessageModal.show(
      context: context,
      title: display._getTitle(l10n),
      message: display._getMessage(),
      type: MessageType.error,
      onConfirm: onRetry,
      confirmText: onRetry != null ? l10n.btnRetry : null,
    );
  }

  static Widget show({
    required Object error,
    String? title,
    VoidCallback? onRetry,
  }) {
    return ErrorDisplay(
      error: error,
      title: title,
      onRetry: onRetry,
    );
  }

  String _getTitle(AppLocalizations l10n) {
    if (title != null) return title!;

    if (error is Failure) {
      final failure = error as Failure;
      switch (failure.code) {
        case 'VALIDATION_ERROR':
          return l10n.errorTitleValidation;
        case 'CONFIG_ERROR':
          return l10n.modalTitleConfigError;
        case 'CONNECTION_ERROR':
          return l10n.modalTitleConnectionError;
        case 'NETWORK_ERROR':
          return l10n.errorTitleNetwork;
        case 'DATABASE_ERROR':
          return l10n.errorTitleDatabase;
        case 'QUERY_ERROR':
          return l10n.queryErrorTitle;
        case 'SERVER_ERROR':
          return l10n.errorTitleServer;
        case 'NOT_FOUND':
          return l10n.errorTitleNotFound;
        default:
          return l10n.modalTitleError;
      }
    }

    return l10n.modalTitleError;
  }

  String _getMessage() {
    return error.toDisplayMessage();
  }

  bool _isRecoverable() {
    if (error is Failure) {
      return (error as Failure).isRecoverable;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recoverable = _isRecoverable();
    final feedbackColors = context.appColors.feedback(AppFeedbackTone.error);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: feedbackColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: feedbackColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.error_badge,
                color: feedbackColors.accent,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _getTitle(l10n),
                  style: context.bodyStrong.copyWith(
                    color: feedbackColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            _getMessage(),
            style: context.bodyText,
          ),
          if (recoverable && onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: l10n.btnRetry,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

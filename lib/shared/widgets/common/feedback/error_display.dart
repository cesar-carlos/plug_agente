import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/errors.dart';
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
    final display = ErrorDisplay(
      error: error,
      title: title,
      onRetry: onRetry,
    );

    return MessageModal.show(
      context: context,
      title: display._getTitle(),
      message: display._getMessage(),
      type: MessageType.error,
      onConfirm: onRetry,
      confirmText: onRetry != null ? 'Tentar Novamente' : null,
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

  String _getTitle() {
    if (title != null) return title!;

    if (error is Failure) {
      final failure = error as Failure;
      switch (failure.code) {
        case 'VALIDATION_ERROR':
          return 'Dados Inválidos';
        case 'CONFIG_ERROR':
          return 'Erro de Configuração';
        case 'CONNECTION_ERROR':
          return 'Erro de Conexão';
        case 'NETWORK_ERROR':
          return 'Erro de Rede';
        case 'DATABASE_ERROR':
          return 'Erro no Banco de Dados';
        case 'QUERY_ERROR':
          return 'Erro na Consulta';
        case 'SERVER_ERROR':
          return 'Erro no Servidor';
        case 'NOT_FOUND':
          return 'Não Encontrado';
        default:
          return 'Erro';
      }
    }

    return 'Erro';
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
    final recoverable = _isRecoverable();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                FluentIcons.error_badge,
                color: AppColors.error,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _getTitle(),
                  style: context.bodyStrong.copyWith(
                    color: AppColors.error,
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
            FilledButton(
              onPressed: onRetry,
              child: Text(
                'Tentar Novamente',
                style: context.bodyText.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

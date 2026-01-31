import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/theme/app_colors.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/shared/widgets/common/message_modal.dart';

/// Standardized error display component.
///
/// Provides consistent error presentation across the application
/// with appropriate actions based on error type and recoverability.
class ErrorDisplay extends StatelessWidget {
  const ErrorDisplay({
    required this.error,
    this.title,
    this.onRetry,
    super.key,
  });

  /// The error to display.
  final Object error;

  /// Optional custom title. If not provided, uses error type.
  final String? title;

  /// Optional retry action for recoverable errors.
  final VoidCallback? onRetry;

  /// Shows error as a modal dialog.
  ///
  /// Use for critical errors that require user attention.
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

  /// Shows error in-place as a widget.
  ///
  /// Use for non-critical errors within a page.
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
    if (error is Failure) {
      return (error as Failure).message;
    }
    return error.toString();
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
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
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getTitle(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getMessage(),
            style: const TextStyle(fontSize: 14),
          ),
          if (recoverable && onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar Novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

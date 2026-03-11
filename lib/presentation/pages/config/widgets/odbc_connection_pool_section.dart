import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/shared/widgets/common/app_button.dart';
import 'package:plug_agente/shared/widgets/common/app_card.dart';
import 'package:plug_agente/shared/widgets/common/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/numeric_field.dart';

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
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _poolSizeController = TextEditingController();
    _loginTimeoutController = TextEditingController();
    _maxResultBufferController = TextEditingController();
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
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final poolSize = int.tryParse(_poolSizeController.text);
    final loginTimeout = int.tryParse(_loginTimeoutController.text);
    final maxResultBuffer = int.tryParse(_maxResultBufferController.text);

    if (poolSize == null || poolSize < 1 || poolSize > 20) {
      _showError('Tamanho do pool deve ser entre 1 e 20');
      return;
    }
    if (loginTimeout == null || loginTimeout < 1 || loginTimeout > 120) {
      _showError('Login timeout deve ser entre 1 e 120 segundos');
      return;
    }
    if (maxResultBuffer == null || maxResultBuffer < 8 || maxResultBuffer > 128) {
      _showError('Buffer de resultados deve ser entre 8 e 128 MB');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = getIt<IOdbcConnectionSettings>();
      await settings.setPoolSize(poolSize);
      await settings.setLoginTimeoutSeconds(loginTimeout);
      await settings.setMaxResultBufferMb(maxResultBuffer);

      final closeResult = await getIt<IConnectionPool>().closeAll();
      final settingsAppliedNow = closeResult.isSuccess();

      if (!mounted) return;
      _showSuccess(settingsAppliedNow);
    } on Object catch (error) {
      _showError('Falha ao salvar configurações avançadas: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    MessageModal.show<void>(
      context: context,
      title: 'Erro',
      message: message,
      type: MessageType.error,
      confirmText: 'OK',
    );
  }

  void _showSuccess(bool settingsAppliedNow) {
    if (!mounted) return;
    final message = settingsAppliedNow
        ? 'As configurações de pool e timeout foram salvas e aplicadas '
              'para novas conexões.'
        : 'As configurações de pool e timeout foram salvas. '
              'As novas opções serão aplicadas gradualmente em '
              'novas conexões.';

    MessageModal.show<void>(
      context: context,
      title: 'Configurações salvas',
      message: message,
      type: MessageType.success,
      confirmText: 'OK',
    );
  }

  @override
  void dispose() {
    _poolSizeController.dispose();
    _loginTimeoutController.dispose();
    _maxResultBufferController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: ProgressRing());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Pool e Timeouts',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pool de Conexões',
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Múltiplas conexões são reutilizadas automaticamente. '
                    'Melhora performance em cenários de alta concorrência.',
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 16),
                  NumericField(
                    label: 'Tamanho máximo do pool',
                    controller: _poolSizeController,
                    hint: '4',
                    minValue: 1,
                    maxValue: 20,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Timeouts',
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  NumericField(
                    label: 'Login timeout (segundos)',
                    controller: _loginTimeoutController,
                    hint: '30',
                    minValue: 1,
                    maxValue: 120,
                  ),
                  const SizedBox(height: 16),
                  NumericField(
                    label: 'Buffer de resultados (MB)',
                    controller: _maxResultBufferController,
                    hint: '32',
                    minValue: 8,
                    maxValue: 128,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tamanho máximo do buffer em memória para resultados de queries. '
                    'Aumentar pode melhorar performance em queries grandes.',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Salvar configurações avançadas',
                    isLoading: _isSaving,
                    onPressed: _saveSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

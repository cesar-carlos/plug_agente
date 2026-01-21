import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../shared/shared.dart';
import '../providers/config_provider.dart';
import '../providers/playground_provider.dart';

class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _showErrorModal(String error) {
    if (!mounted) return;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show(context: navigatorContext, title: 'Erro', message: error, type: MessageType.error);
  }

  void _showConnectionStatusModal(String status, bool isSuccess) {
    if (!mounted) return;
    final navigatorContext = Navigator.of(context, rootNavigator: true).context;
    MessageModal.show(
      context: navigatorContext,
      title: 'Status da Conexão',
      message: status,
      type: isSuccess ? MessageType.success : MessageType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Playground Database')),
      content: Consumer2<PlaygroundProvider, ConfigProvider>(
        builder: (context, playgroundProvider, configProvider, _) {
          final config = configProvider.currentConfig;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SqlEditor(
                  controller: _queryController,
                  onChanged: (value) {
                    playgroundProvider.setQuery(value);
                  },
                ),
                const SizedBox(height: 16),
                SqlActionBar(
                  onExecute: () async {
                    playgroundProvider.setQuery(_queryController.text);
                    await playgroundProvider.executeQuery();
                    final error = playgroundProvider.error;
                    if (error != null) {
                      _showErrorModal(error);
                    }
                  },
                  onTestConnection: config != null
                      ? () async {
                          await playgroundProvider.testConnection(config);
                          final connectionStatus = playgroundProvider.connectionStatus;
                          final error = playgroundProvider.error;
                          if (connectionStatus != null) {
                            final isSuccess = connectionStatus.contains('sucesso');
                            _showConnectionStatusModal(connectionStatus, isSuccess);
                          } else if (error != null) {
                            _showErrorModal(error);
                          }
                        }
                      : null,
                  onClear: () {
                    _queryController.clear();
                    playgroundProvider.clearResults();
                  },
                  isExecuting: playgroundProvider.isLoading,
                ),
                const SizedBox(height: 16),
                if (playgroundProvider.executionTime != null || playgroundProvider.affectedRows != null) ...[
                  QueryResultInfoCard(
                    executionTime: playgroundProvider.executionTime,
                    affectedRows: playgroundProvider.affectedRows,
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 400,
                  child: QueryResultsSection(
                    results: playgroundProvider.results,
                    isLoading: playgroundProvider.isLoading,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

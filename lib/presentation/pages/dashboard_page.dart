import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/di/service_locator.dart';
import '../../application/services/query_processing_service.dart';
import '../../domain/repositories/i_transport_client.dart';
import '../widgets/connection_status_widget.dart';
import '../widgets/websocket_log_viewer.dart';
import '../providers/websocket_log_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final QueryProcessingService _queryProcessingService;

  @override
  void initState() {
    super.initState();
    _queryProcessingService = getIt<QueryProcessingService>();
    _queryProcessingService.start();
    _setupWebSocketLogging();
  }

  void _setupWebSocketLogging() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final logProvider = Provider.of<WebSocketLogProvider>(context, listen: false);
      try {
        final transportClient = getIt<ITransportClient>();
        transportClient.setMessageCallback((direction, event, data) {
          logProvider.addMessage(direction, event, data);
        });
      } catch (e) {
        // Transport client might not be initialized yet
      }
    });
  }

  @override
  void dispose() {
    _queryProcessingService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Dashboard')),
      content: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plug Database',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Monitor your agent status and database connections here.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const ConnectionStatusWidget(),
            const SizedBox(height: 24),
            const Expanded(
              child: WebSocketLogViewer(),
            ),
          ],
        ),
      ),
    );
  }
}

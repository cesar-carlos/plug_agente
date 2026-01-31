import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/query_processing_service.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_viewer.dart';
import 'package:provider/provider.dart';

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
      final logProvider = Provider.of<WebSocketLogProvider>(
        context,
        listen: false,
      );
      try {
        final transportClient = getIt<ITransportClient>();
        transportClient.setMessageCallback(logProvider.addMessage);
      } on Exception {
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
    return const ScaffoldPage(
      header: PageHeader(title: Text('Dashboard')),
      content: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plug Database',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Monitor your agent status and database connections here.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 32),
            ConnectionStatusWidget(),
            SizedBox(height: 24),
            Expanded(child: WebSocketLogViewer()),
          ],
        ),
      ),
    );
  }
}

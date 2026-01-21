import 'package:fluent_ui/fluent_ui.dart';
import 'query_result_data_grid.dart';
import '../common/centered_message.dart';

class QueryResultsSection extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final bool isLoading;

  const QueryResultsSection({
    super.key,
    required this.results,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: ProgressRing(),
      );
    }

    if (results.isEmpty) {
      return const CenteredMessage(
        title: 'Sem resultados',
        message: 'Execute uma consulta SELECT para ver os resultados aqui.',
        icon: FluentIcons.table,
      );
    }

    return QueryResultDataGrid(data: results);
  }
}

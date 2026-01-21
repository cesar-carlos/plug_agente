import 'package:fluent_ui/fluent_ui.dart';

import '../common/app_card.dart';

class QueryResultInfoCard extends StatelessWidget {
  final DateTime? executionTime;
  final int? affectedRows;

  const QueryResultInfoCard({super.key, this.executionTime, this.affectedRows});

  @override
  Widget build(BuildContext context) {
    if (executionTime == null && affectedRows == null) {
      return const SizedBox.shrink();
    }

    return AppCard(
      child: Row(
        children: [
          if (executionTime != null) ...[
            const Icon(FluentIcons.clock),
            const SizedBox(width: 8),
            Text('Executado em: ${_formatDateTime(executionTime!)}'),
          ],
          if (executionTime != null && affectedRows != null) ...[const SizedBox(width: 24)],
          if (affectedRows != null) ...[
            const Icon(FluentIcons.table),
            const SizedBox(width: 8),
            Text('Linhas: $affectedRows'),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }
}

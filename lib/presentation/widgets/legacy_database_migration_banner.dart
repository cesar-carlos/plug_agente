import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/diagnostics/legacy_database_migration_status.dart';

class LegacyDatabaseMigrationBanner extends StatelessWidget {
  const LegacyDatabaseMigrationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final failureMessage = LegacyDatabaseMigrationStatus.lastFailureMessage;
    if (failureMessage == null || failureMessage.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InfoBar(
        title: const Text('Legacy database migration failed'),
        content: Text(failureMessage),
        severity: InfoBarSeverity.warning,
        isLong: true,
      ),
    );
  }
}

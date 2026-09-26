import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_sql_investigation_item.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  testWidgets('should show user message and stable reason code together', (tester) async {
    const userMessage =
        'Nao foi possivel identificar as tabelas da consulta para autorizacao. Revise a consulta enviada.';
    await tester.pumpWidget(
      FluentApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WebSocketLogSqlInvestigationItem(
          event: SqlInvestigationEvent(
            timestamp: DateTime(2026, 9, 26, 8, 18, 25),
            kind: SqlInvestigationKind.authorizationDenied,
            method: 'sql.execute',
            originalSql: 'SELECT 1',
            reason: 'unsupported_sql',
            userMessage: userMessage,
          ),
          l10n: l10n,
        ),
      ),
    );

    expect(find.textContaining(userMessage), findsOneWidget);
    expect(find.textContaining('unsupported_sql'), findsOneWidget);
    expect(find.textContaining('Motivo:'), findsOneWidget);
    expect(find.textContaining('Código:'), findsOneWidget);
  });
}

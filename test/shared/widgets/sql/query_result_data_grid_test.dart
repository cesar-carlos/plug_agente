import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/sql/query_result_data_grid.dart';
import 'package:pluto_grid/pluto_grid.dart';

Widget _app(
  List<Map<String, dynamic>> rows, {
  List<Map<String, dynamic>>? metadata,
  int revision = 0,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return FluentApp(
    locale: const Locale('pt', 'BR'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: FluentThemeData(brightness: brightness),
    home: ScaffoldPage(
      content: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: QueryResultDataGrid(
          data: rows,
          columnMetadata: metadata,
          dataRevision: revision,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders empty results in Portuguese', (tester) async {
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(QueryResultDataGrid));
    expect(find.text(AppLocalizations.of(context)!.queryNoResults), findsOneWidget);
    expect(find.byType(PlutoGrid), findsNothing);
  });

  testWidgets('preserves SQL values and uses metadata titles', (tester) async {
    await tester.pumpWidget(
      _app(
        [
          {'amount': 12.3456789, 'code': '0012', 'optional': null},
        ],
        metadata: [
          {'name': 'AMOUNT', 'length': 20},
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('12.3456789'), findsOneWidget);
    expect(find.text('0012'), findsOneWidget);
    expect(find.text('null'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sorts numeric results numerically when clicking the header', (tester) async {
    final rows = <Map<String, dynamic>>[
      {'amount': 100},
      {'amount': 2},
      {'amount': 11},
    ];
    await tester.pumpWidget(_app(rows));
    await tester.pumpAndSettle();
    await tester.tap(find.text('amount'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('2')).dy, lessThan(tester.getTopLeft(find.text('11')).dy));
    expect(tester.getTopLeft(find.text('11')).dy, lessThan(tester.getTopLeft(find.text('100')).dy));
    expect(rows.first['amount'], 100);
  });

  testWidgets('filters results and restores them after clearing the filter', (tester) async {
    await tester.pumpWidget(
      _app([
        {'name': 'Alice'},
        {'name': 'Bruno'},
      ]),
    );
    await tester.pumpAndSettle();
    final filter = find.byType(material.TextField).first;
    expect(tester.widget<material.TextField>(filter).decoration?.hintText, 'Contenha');
    await tester.tap(filter);
    await tester.enterText(filter, 'Alice');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsNothing);
    await tester.enterText(filter, '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('keeps result cells read-only and supports keyboard navigation', (tester) async {
    await tester.pumpWidget(
      _app([
        {'name': 'Alice'},
        {'name': 'Bruno'},
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final state = tester.state<PlutoGridState>(find.byType(PlutoGrid)).stateManager;
    expect(state.currentCell?.value, 'Bruno');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(state.isEditing, isFalse);
    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('retains sorting and filters when streamed results are refreshed', (tester) async {
    await tester.pumpWidget(
      _app([
        {'name': 'Alice', 'amount': 100},
        {'name': 'Bruno', 'amount': 2},
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('amount'));
    final filter = find.byType(material.TextField).first;
    await tester.tap(filter);
    await tester.enterText(filter, 'Alice');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app([
        {'name': 'Alice', 'amount': 100},
        {'name': 'Bruno', 'amount': 2},
        {'name': 'Alice', 'amount': 11},
      ], revision: 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bruno'), findsNothing);
    expect(tester.getTopLeft(find.text('11')).dy, lessThan(tester.getTopLeft(find.text('100')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshes same-length results, in-place revisions and changed columns', (tester) async {
    var rows = <Map<String, dynamic>>[
      {'name': 'old'},
    ];
    await tester.pumpWidget(_app(rows));
    await tester.pumpAndSettle();
    rows = [
      {'name': 'replacement'},
    ];
    await tester.pumpWidget(_app(rows));
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(find.text('replacement'), findsOneWidget);
    rows.first['name'] = 'revised';
    await tester.pumpWidget(_app(rows, revision: 1));
    await tester.pumpAndSettle();
    expect(find.text('revised'), findsOneWidget);
    await tester.pumpWidget(
      _app([
        {'other': 'new schema'},
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('other'), findsOneWidget);
    expect(find.text('new schema'), findsOneWidget);
    expect(find.text('revised'), findsNothing);
  });

  testWidgets('virtualizes large results and disables costly sorting and filtering', (tester) async {
    await tester.pumpWidget(_app(List.generate(10001, (index) => {'name': 'record $index'})));
    await tester.pumpAndSettle();
    expect(find.text('record 0'), findsOneWidget);
    expect(find.text('record 10000'), findsNothing);
    expect(find.byType(material.TextField), findsNothing);
    await tester.tap(find.text('name'));
    await tester.pumpAndSettle();
    final state = tester.state<PlutoGridState>(find.byType(PlutoGrid)).stateManager;
    expect(state.columns.single.sort, PlutoColumnSort.none);
    state.scroll.vertical!.jumpTo(state.scroll.maxScrollVertical);
    await tester.pumpAndSettle();
    expect(find.text('record 10000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports dark theme and large text in a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(500, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        [
          {'description': 'A long result value', 'number': 123},
        ],
        brightness: Brightness.dark,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A long result value'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/shared/widgets/common/layout/config_list_item.dart';

void main() {
  testWidgets('invokes onTap from pointer and keyboard', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: ConfigListItem(
            title: 'Produção',
            subtitle: 'SQL Server',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Produção'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 2);
  });
}

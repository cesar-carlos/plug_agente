import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/shared/widgets/common/form/app_checkbox.dart';

void main() {
  testWidgets('long labels wrap inside the remaining width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(180, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const FluentApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: ScaffoldPage(
            content: AppCheckbox(
              checked: false,
              onChanged: _ignore,
              content: Text('Run this action with an elevated token and a very long explanation'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Text)).width, lessThan(180));
  });
}

void _ignore(bool? _) {}

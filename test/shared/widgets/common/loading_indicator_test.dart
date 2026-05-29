import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/shared/widgets/common/feedback/loading_indicator.dart';

void main() {
  group('LoadingIndicator', () {
    Widget wrap(Widget child) {
      return FluentApp(
        home: ScaffoldPage(content: child),
      );
    }

    testWidgets('should render a ProgressRing', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));

      expect(find.byType(ProgressRing), findsOneWidget);
    });

    testWidgets('should render Center widget', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));

      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('should NOT render message when null', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('should render message when provided', (tester) async {
      const message = 'Loading data...';

      await tester.pumpWidget(wrap(const LoadingIndicator(message: message)));

      expect(find.text(message), findsOneWidget);
    });

    testWidgets('should use a MainAxisSize.min Column', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator()));

      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(LoadingIndicator),
          matching: find.byType(Column),
        ),
      );
      expect(column.mainAxisSize, MainAxisSize.min);
    });
  });
}

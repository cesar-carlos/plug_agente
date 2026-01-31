import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/shared/widgets/common/app_card.dart';

void main() {
  group('AppCard', () {
    testWidgets('should render child', (tester) async {
      // Arrange
      const child = Text('Test Content');

      // Act
      await tester.pumpWidget(
        const FluentApp(
          home: ScaffoldPage(
            content: AppCard(child: child),
          ),
        ),
      );

      // Assert
      expect(find.text('Test Content'), findsOneWidget);
    });

    testWidgets('should render Card widget', (tester) async {
      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('should use default padding when not provided', (tester) async {
      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.padding, const EdgeInsets.all(16));
    });

    testWidgets('should use custom padding when provided', (tester) async {
      // Arrange
      const customPadding = EdgeInsets.all(24);

      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              padding: customPadding,
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.padding, customPadding);
    });

    testWidgets('should use default margin when not provided', (tester) async {
      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.margin, const EdgeInsets.all(0));
    });

    testWidgets('should use custom margin when provided', (tester) async {
      // Arrange
      const customMargin = EdgeInsets.symmetric(horizontal: 16);

      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              margin: customMargin,
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.margin, customMargin);
    });

    testWidgets('should NOT wrap in GestureDetector when onTap is null', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              child: Container(),
            ),
          ),
        ),
      );

      // Assert
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('should wrap in GestureDetector when onTap is provided', (
      tester,
    ) async {
      // Act
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              onTap: () {},
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      // Assert
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('should call onTap when tapped', (tester) async {
      // Arrange
      var tapped = false;

      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: AppCard(
              onTap: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      // Assert
      expect(tapped, isTrue);
    });
  });
}

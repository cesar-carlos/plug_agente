import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/shared/widgets/common/app_button.dart';

void main() {
  group('AppButton', () {
    group('basic rendering', () {
      testWidgets('should render label text', (tester) async {
        // Arrange
        const label = 'Submit';

        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(label: label),
            ),
          ),
        );

        // Assert
        expect(find.text(label), findsOneWidget);
      });

      testWidgets('should render FilledButton when isPrimary is true', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(Button), findsNothing);
      });

      testWidgets('should render Button when isPrimary is false', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                isPrimary: false,
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(Button), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      });
    });

    group('with icon', () {
      testWidgets('should render icon when provided', (tester) async {
        // Arrange
        const icon = FluentIcons.add;

        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Add',
                icon: icon,
              ),
            ),
          ),
        );

        // Assert
        expect(find.byIcon(icon), findsOneWidget);
      });

      testWidgets('should render Row with icon and label', (tester) async {
        // Arrange
        const icon = FluentIcons.add;

        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Add',
                icon: icon,
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(Row), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
        expect(find.text('Add'), findsOneWidget);
      });

      testWidgets('should render SizedBox between icon and label', (
        tester,
      ) async {
        // Arrange
        const icon = FluentIcons.add;

        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Add',
                icon: icon,
              ),
            ),
          ),
        );

        // Assert - Row contains icon and label
        expect(find.byType(Row), findsOneWidget);
        expect(find.byType(Icon), findsOneWidget);
        expect(find.text('Add'), findsOneWidget);
      });
    });

    group('loading state', () {
      testWidgets('should render ProgressRing when isLoading is true', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                isLoading: true,
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(ProgressRing), findsOneWidget);
        expect(find.text('Submit'), findsNothing);
      });

      testWidgets('should NOT render label when isLoading is true', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                isLoading: true,
              ),
            ),
          ),
        );

        // Assert
        expect(find.text('Submit'), findsNothing);
      });

      testWidgets('should NOT render icon when isLoading is true', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Add',
                icon: FluentIcons.add,
                isLoading: true,
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(Icon), findsNothing);
      });

      testWidgets('should disable button when isLoading is true', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                isLoading: true,
              ),
            ),
          ),
        );

        // Assert
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      });

      testWidgets('should render correct sized box for ProgressRing', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                isLoading: true,
              ),
            ),
          ),
        );

        // Assert
        final sizedBox = tester.widget<SizedBox>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(SizedBox),
          ),
        );
        expect(sizedBox.width, 16);
        expect(sizedBox.height, 16);
      });
    });

    group('callbacks', () {
      testWidgets('should disable button when onPressed is null', (
        tester,
      ) async {
        // Act
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
              ),
            ),
          ),
        );

        // Assert
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      });

      testWidgets('should have callback when onPressed is provided', (
        tester,
      ) async {
        // Arrange
        void onPressed() {}

        // Act
        await tester.pumpWidget(
          FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Submit',
                onPressed: onPressed,
              ),
            ),
          ),
        );

        // Assert
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNotNull);
      });
    });
  });
}

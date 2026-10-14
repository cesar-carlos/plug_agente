import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

void _noop() {}

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
        expect(find.text('Submit'), findsOneWidget);
      });

      testWidgets('keeps the label laid out while loading', (tester) async {
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

        expect(find.text('Submit'), findsOneWidget);
        expect(find.byType(ProgressRing), findsOneWidget);
      });

      testWidgets('keeps the icon laid out while loading', (tester) async {
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

        expect(find.byIcon(FluentIcons.add), findsOneWidget);
        expect(find.byType(ProgressRing), findsOneWidget);
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
        expect(tester.getSize(find.byType(ProgressRing)), const Size(16, 16));
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

    group('tooltip', () {
      testWidgets('should wrap with Tooltip when tooltip is non-empty', (
        tester,
      ) async {
        await tester.pumpWidget(
          FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Go',
                tooltip: 'Runs the action',
                onPressed: () {},
              ),
            ),
          ),
        );

        expect(find.byType(Tooltip), findsOneWidget);
      });
    });

    group('semantics', () {
      testWidgets('should expose loading label for screen readers when loading', (
        tester,
      ) async {
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Save',
                isLoading: true,
              ),
            ),
          ),
        );

        expect(find.bySemanticsLabel('Save, loading'), findsOneWidget);
      });

      testWidgets('uses the localized loading suffix', (tester) async {
        await tester.pumpWidget(
          const FluentApp(
            locale: Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ScaffoldPage(
              content: AppButton(label: 'Salvar', isLoading: true),
            ),
          ),
        );

        expect(find.bySemanticsLabel('Salvar, carregando'), findsOneWidget);
      });

      testWidgets('keeps the idle width while loading', (tester) async {
        const label = 'Submit action';

        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(label: label, onPressed: _noop),
            ),
          ),
        );
        await tester.pump();
        final idle = tester.getSize(find.byType(FilledButton));

        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(label: label, isLoading: true, onPressed: _noop),
            ),
          ),
        );
        await tester.pump();

        expect(tester.getSize(find.byType(FilledButton)), idle);
      });

      testWidgets('should use custom semanticsLabel when provided', (
        tester,
      ) async {
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Save',
                semanticsLabel: 'Save document',
              ),
            ),
          ),
        );

        expect(find.bySemanticsLabel('Save document'), findsOneWidget);
      });
    });

    group('destructive primary', () {
      testWidgets('should render FilledButton when isDestructive is true', (
        tester,
      ) async {
        await tester.pumpWidget(
          const FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Delete',
                isDestructive: true,
              ),
            ),
          ),
        );

        expect(find.byType(FilledButton), findsOneWidget);
      });
    });

    group('focus', () {
      testWidgets('should wire focusNode to FilledButton', (tester) async {
        final focusNode = FocusNode();

        await tester.pumpWidget(
          FluentApp(
            home: ScaffoldPage(
              content: AppButton(
                label: 'Focus me',
                focusNode: focusNode,
                onPressed: () {},
              ),
            ),
          ),
        );

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.focusNode, focusNode);

        focusNode.dispose();
      });
    });
  });
}

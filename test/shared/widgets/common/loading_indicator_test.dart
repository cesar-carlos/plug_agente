import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/shared/widgets/common/loading_indicator.dart';

void main() {
  group('LoadingIndicator', () {
    testWidgets('should render CircularProgressIndicator', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should render Center widget', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('should render Card widget', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('should NOT render message when null', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('should render message when provided', (tester) async {
      // Arrange
      const message = 'Loading data...';

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(message: message),
          ),
        ),
      );

      // Assert
      expect(find.text(message), findsOneWidget);
    });

    testWidgets('should render SizedBox between indicator and message', (
      tester,
    ) async {
      // Arrange
      const message = 'Loading...';

      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(message: message),
          ),
        ),
      );

      // Assert
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('should use Column layout', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      expect(find.byType(Column), findsOneWidget);
    });

    testWidgets('should use MainAxisSize.min for Column', (tester) async {
      // Act
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingIndicator(),
          ),
        ),
      );

      // Assert
      final column = tester.widget<Column>(find.byType(Column));
      expect(column.mainAxisSize, MainAxisSize.min);
    });
  });
}

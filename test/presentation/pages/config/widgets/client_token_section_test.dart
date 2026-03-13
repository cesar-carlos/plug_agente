import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_section.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockCreateClientToken extends Mock implements CreateClientToken {}

class MockListClientTokens extends Mock implements ListClientTokens {}

class MockUpdateClientToken extends Mock implements UpdateClientToken {}

class MockRevokeClientToken extends Mock implements RevokeClientToken {}

class MockDeleteClientToken extends Mock implements DeleteClientToken {}

void main() {
  group('ClientTokenSection', () {
    late MockCreateClientToken mockCreateClientToken;
    late MockListClientTokens mockListClientTokens;
    late MockUpdateClientToken mockUpdateClientToken;
    late MockRevokeClientToken mockRevokeClientToken;
    late MockDeleteClientToken mockDeleteClientToken;
    late ClientTokenProvider provider;

    setUp(() {
      mockCreateClientToken = MockCreateClientToken();
      mockListClientTokens = MockListClientTokens();
      mockUpdateClientToken = MockUpdateClientToken();
      mockRevokeClientToken = MockRevokeClientToken();
      mockDeleteClientToken = MockDeleteClientToken();

      when(
        () => mockListClientTokens(),
      ).thenAnswer((_) async => const Success(<ClientTokenSummary>[]));

      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockUpdateClientToken,
        mockListClientTokens,
        mockRevokeClientToken,
        mockDeleteClientToken,
      );
    });

    testWidgets('should add rule and render it in rules grid', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.ctButtonNewToken));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.ctNoRulesAdded), findsOneWidget);

      await tester.tap(find.text(AppStrings.ctButtonAddRule));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.ctDialogSaveRule), findsOneWidget);

      await tester.enterText(find.byType(TextBox).last, 'dbo.clientes');
      await tester.tap(find.text(AppStrings.ctDialogSaveRule));
      await tester.pumpAndSettle();

      expect(find.text('dbo.clientes'), findsOneWidget);
      expect(find.text(AppStrings.ctNoRulesAdded), findsNothing);
    });

    testWidgets('should remove existing rule row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.ctButtonNewToken));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.ctButtonAddRule));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextBox).last, 'dbo.clientes');
      await tester.tap(find.text(AppStrings.ctDialogSaveRule));
      await tester.pumpAndSettle();

      final removeButtons = find.byIcon(FluentIcons.delete);
      await tester.ensureVisible(removeButtons.last);
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('dbo.clientes'), findsNothing);
    });

    testWidgets(
      'should show validation error when payload is invalid json',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(AppStrings.ctButtonNewToken));
        await tester.pumpAndSettle();

        final payloadField = find.byWidgetPredicate((widget) {
          return widget is TextBox && widget.maxLines == 4;
        });
        await tester.enterText(payloadField, '{invalid json');
        await tester.ensureVisible(find.text(AppStrings.ctButtonCreateToken));
        await tester.tap(find.text(AppStrings.ctButtonCreateToken));
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.ctErrorPayloadInvalidJson), findsOneWidget);
      },
    );
  });
}

Widget _buildWidget(ClientTokenProvider provider) {
  return FluentApp(
    home: ChangeNotifierProvider<ClientTokenProvider>.value(
      value: provider,
      child: const NavigationView(
        content: ScaffoldPage(
          content: SingleChildScrollView(
            child: ClientTokenSection(),
          ),
        ),
      ),
    ),
  );
}

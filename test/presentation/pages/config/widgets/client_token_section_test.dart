import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_section.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockCreateClientToken extends Mock implements CreateClientToken {}

class MockListClientTokens extends Mock implements ListClientTokens {}

class MockRevokeClientToken extends Mock implements RevokeClientToken {}

class MockDeleteClientToken extends Mock implements DeleteClientToken {}

void main() {
  group('ClientTokenSection', () {
    late MockCreateClientToken mockCreateClientToken;
    late MockListClientTokens mockListClientTokens;
    late MockRevokeClientToken mockRevokeClientToken;
    late MockDeleteClientToken mockDeleteClientToken;
    late ClientTokenProvider provider;

    setUp(() {
      mockCreateClientToken = MockCreateClientToken();
      mockListClientTokens = MockListClientTokens();
      mockRevokeClientToken = MockRevokeClientToken();
      mockDeleteClientToken = MockDeleteClientToken();

      when(
        () => mockListClientTokens(),
      ).thenAnswer((_) async => const Success(<ClientTokenSummary>[]));

      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockListClientTokens,
        mockRevokeClientToken,
        mockDeleteClientToken,
      );
    });

    testWidgets('should add and remove rule rows', (tester) async {
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      expect(find.text('Regra 1'), findsOneWidget);
      expect(find.text('Regra 2'), findsNothing);

      await tester.tap(find.text('Adicionar regra'));
      await tester.pumpAndSettle();

      expect(find.text('Regra 2'), findsOneWidget);

      final removeButtons = find.byIcon(FluentIcons.delete);
      await tester.ensureVisible(removeButtons.last);
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Regra 2'), findsNothing);
      expect(find.text('Regra 1'), findsOneWidget);
    });

    testWidgets(
      'should show validation error when client id is empty',
      (tester) async {
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Criar token'));
        await tester.tap(find.text('Criar token'));
        await tester.pumpAndSettle();

        expect(
          find.text('Informe o client_id para criar o token.'),
          findsOneWidget,
        );
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

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
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
  late AppLocalizations ptL10n;

  setUpAll(() async {
    registerFallbackValue(const ClientTokenListQuery());
    registerFallbackValue(
      const ClientTokenCreateRequest(
        clientId: 'fallback',
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: <ClientTokenRule>[],
      ),
    );
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

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
        () => mockListClientTokens(query: any(named: 'query')),
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

      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.ctNoRulesAdded), findsOneWidget);

      await tester.tap(find.text(ptL10n.ctButtonAddRule));
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.ctDialogSaveRule), findsOneWidget);

      await tester.enterText(find.byType(TextBox).last, 'dbo.clientes');
      await tester.tap(find.text(ptL10n.ctDialogSaveRule));
      await tester.pumpAndSettle();

      expect(find.text('dbo.clientes'), findsOneWidget);
      expect(find.text(ptL10n.ctNoRulesAdded), findsNothing);
    });

    testWidgets('should remove existing rule row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.ctButtonAddRule));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextBox).last, 'dbo.clientes');
      await tester.tap(find.text(ptL10n.ctDialogSaveRule));
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

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        final payloadField = find.byWidgetPredicate((widget) {
          return widget is TextBox && widget.maxLines == 4;
        });
        await tester.enterText(payloadField, '{invalid json');
        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pumpAndSettle();

        expect(find.text(ptL10n.ctErrorPayloadInvalidJson), findsOneWidget);
      },
    );

    testWidgets(
      'create token dialog lays out without overflow on short viewport',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(920, 480));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(ptL10n.ctDialogCreateTokenTitle),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'edit token dialog lays out without overflow on short viewport',
      (tester) async {
        final token = ClientTokenSummary(
          id: 't1',
          clientId: 'c1',
          createdAt: DateTime.utc(2025),
          isRevoked: false,
          allTables: false,
          allViews: false,
          allPermissions: true,
          rules: const <ClientTokenRule>[],
        );
        when(
          () => mockListClientTokens(query: any(named: 'query')),
        ).thenAnswer((_) async => Success(<ClientTokenSummary>[token]));

        await tester.binding.setSurfaceSize(const Size(920, 480));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(FluentIcons.edit).first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(ptL10n.ctDialogEditTokenTitle), findsOneWidget);
      },
    );

    testWidgets('escape closes create token dialog', (tester) async {
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.ctDialogCreateTokenTitle), findsNothing);
    });

    testWidgets(
      'escape does not close dialog while create request is in flight',
      (tester) async {
        final completer = Completer<Result<String>>();
        when(
          () => mockCreateClientToken(any()),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctFlagAllPermissions));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(find.text(ptL10n.ctDialogCreateTokenTitle), findsOneWidget);

        completer.complete(const Success('new-token'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'agent field done action submits create when form is valid',
      (tester) async {
        when(
          () => mockCreateClientToken(any()),
        ).thenAnswer((_) async => const Success('tok'));

        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctFlagAllPermissions));
        await tester.pumpAndSettle();

        final agentField = find.byWidgetPredicate(
          (Object? widget) => widget is TextBox && widget.placeholder == ptL10n.ctHintAgentId,
        );
        await tester.tap(agentField);
        await tester.pumpAndSettle();
        await tester.enterText(agentField, 'agent-x');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(() => mockCreateClientToken(any())).called(1);
      },
    );
  });
}

Widget _buildWidget(ClientTokenProvider provider) {
  return FluentApp(
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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

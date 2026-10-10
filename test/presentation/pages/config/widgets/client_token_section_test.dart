import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/count_active_client_tokens.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/list_client_token_page.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_creation_result.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_row_actions.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_coordinator.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_list_preferences.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_section.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

import '../../../../helpers/client_token_test_loaders.dart';
import '../../../../helpers/memory_token_secret_store.dart';

class MockCreateClientToken extends Mock implements CreateClientToken {}

class MockCountActiveClientTokens extends Mock implements CountActiveClientTokens {}

class MockListClientTokens extends Mock implements ListClientTokens {}

class MockUpdateClientToken extends Mock implements UpdateClientToken {}

class MockGetClientTokenSecret extends Mock implements GetClientTokenSecret {}

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
    late MockGetClientTokenSecret mockGetClientTokenSecret;
    late MockRevokeClientToken mockRevokeClientToken;
    late MockDeleteClientToken mockDeleteClientToken;
    late ClientTokenProvider provider;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      mockCreateClientToken = MockCreateClientToken();
      mockListClientTokens = MockListClientTokens();
      mockUpdateClientToken = MockUpdateClientToken();
      mockGetClientTokenSecret = MockGetClientTokenSecret();
      mockRevokeClientToken = MockRevokeClientToken();
      mockDeleteClientToken = MockDeleteClientToken();

      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => const Success(<ClientTokenSummary>[]));

      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockUpdateClientToken,
        ClientTokenTestPageLoader(mockListClientTokens),
        mockGetClientTokenSecret,
        mockRevokeClientToken,
        mockDeleteClientToken,
        countActiveClientTokens: FixedClientTokenTestCounter(),
      );
      when(
        () => mockGetClientTokenSecret(any()),
      ).thenAnswer(
        (_) async => const Success(ClientTokenSecretLookup(tokenValue: null)),
      );
    });

    testWidgets('opening and cancelling a form preserves the failed page query until retry', (tester) async {
      final tokens = List.generate(
        101,
        (i) => ClientTokenSummary(
          id: 'id-$i',
          clientId: 'client-$i',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          rules: const [],
        ),
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      expect(provider.tokens.last.id, 'id-49');
      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => Failure(domain.DatabaseFailure('injected read failure')));
      tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).onChanged!(100);
      await tester.pumpAndSettle();
      expect(provider.pageSize, 50);
      expect(provider.hasListLoadError, isTrue);
      expect(
        tester
            .widget<AppButton>(find.byWidgetPredicate((w) => w is AppButton && w.label == ptL10n.queryPaginationNext))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(provider.hasListLoadError, isTrue);
      expect(provider.pageSize, 50);
      expect(
        tester
            .widget<AppButton>(find.byWidgetPredicate((w) => w is AppButton && w.label == ptL10n.queryPaginationNext))
            .onPressed,
        isNull,
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await tester.tap(find.text(ptL10n.btnRetry));
      await tester.pumpAndSettle();
      expect(provider.tokens.last.id, 'id-99');
      await tester.tap(find.text(ptL10n.queryPaginationNext));
      await tester.pumpAndSettle();
      expect(provider.loadedListQuery!.pageSize, 100);
      expect(provider.currentPage, 2);
      expect(provider.tokens.single.id, 'id-100');
    });

    testWidgets('stale-list retry admits only one read before the next frame', (tester) async {
      when(() => mockCreateClientToken.createWithIdentity(any())).thenAnswer(
        (_) async =>
            const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'synthetic-review-secret')),
      );
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
      await tester.tap(find.text(ptL10n.ctFlagAllTables));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ptL10n.ctPermissionRead));
      await tester.tap(find.text(ptL10n.ctPermissionRead));
      await tester.pumpAndSettle();
      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => Failure(domain.DatabaseFailure('injected refresh failure')));
      await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
      await tester.tap(find.text(ptL10n.ctButtonCreateToken));
      await tester.pumpAndSettle();
      expect(provider.isListStale, isTrue);
      final reads = <Completer<Result<List<ClientTokenSummary>>>>[];
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) {
        final read = Completer<Result<List<ClientTokenSummary>>>();
        reads.add(read);
        return read.future;
      });
      await tester.tap(find.text(ptL10n.btnRetry));
      expect(provider.isQueryPending, isTrue);
      await tester.tap(find.text(ptL10n.btnRetry));
      await tester.pump();
      expect(reads.length, 1);
      expect(find.text(ptL10n.btnRetry), findsNothing);
      for (final read in reads) {
        read.complete(const Success(<ClientTokenSummary>[]));
      }
      await tester.pumpAndSettle();
      verify(() => mockCreateClientToken.createWithIdentity(any())).called(1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('retry stays exclusive while the global count is pending', (tester) async {
      final count = MockCountActiveClientTokens();
      final pendingCount = Completer<Result<int>>();
      when(count.call).thenAnswer((_) => pendingCount.future);
      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockUpdateClientToken,
        ClientTokenTestPageLoader(mockListClientTokens),
        mockGetClientTokenSecret,
        mockRevokeClientToken,
        mockDeleteClientToken,
        countActiveClientTokens: count,
      );
      final controller = ClientTokenSectionController(settingsStoreLookup: () => null, onSectionChanged: () {});
      addTearDown(controller.dispose);
      final coordinator = ClientTokenSectionCoordinator(controller: controller);
      final first = coordinator.refreshList(provider);
      await tester.pump();
      expect(provider.isQueryPending, isFalse);
      final second = coordinator.refreshList(provider);
      verify(() => mockListClientTokens(query: any(named: 'query'))).called(1);
      verify(count.call).called(1);
      pendingCount.complete(const Success(0));
      await Future.wait([first, second]);
    });

    testWidgets('navigation uses the confirmed size even if the controller has an uncommitted size', (tester) async {
      final tokens = List.generate(
        101,
        (i) => ClientTokenSummary(
          id: 'id-$i',
          clientId: 'client-$i',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: false,
          rules: const [],
        ),
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await provider.loadTokens();
      final controller = ClientTokenSectionController(settingsStoreLookup: () => null, onSectionChanged: () {});
      addTearDown(controller.dispose);
      controller.pageSize = 100;
      await ClientTokenSectionCoordinator(controller: controller).changePage(provider, 2);
      expect(provider.pageSize, 50);
      expect(provider.tokens.first.id, 'id-50');
      expect(provider.tokens.last.id, 'id-99');
    });

    for (final action in ['copy', 'revoke', 'delete', 'failed-copy']) {
      testWidgets('created-secret feedback handles $action with the persisted identity', (tester) async {
        final audit = _RecordingTokenAuditStore();
        provider = ClientTokenProvider(
          mockCreateClientToken,
          mockUpdateClientToken,
          ClientTokenTestPageLoader(mockListClientTokens),
          mockGetClientTokenSecret,
          mockRevokeClientToken,
          mockDeleteClientToken,
          countActiveClientTokens: FixedClientTokenTestCounter(),
          tokenAuditStore: audit,
        );
        String? copiedText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              if (action == 'failed-copy') throw PlatformException(code: 'clipboard_unavailable');
              copiedText = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final token = ClientTokenSummary(
          id: 'token-1',
          clientId: 'client-1',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: true,
          rules: const [],
        );
        var rows = <ClientTokenSummary>[];
        when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(rows));
        when(() => mockCreateClientToken.createWithIdentity(any())).thenAnswer((_) async {
          rows = [token];
          return const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'created-secret'));
        });
        when(() => mockRevokeClientToken('token-1')).thenAnswer((_) async {
          rows = [token.copyWith(isRevoked: true, version: 2)];
          return const Success(unit);
        });
        when(() => mockDeleteClientToken('token-1')).thenAnswer((_) async {
          rows = [];
          return const Success(unit);
        });
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
        await tester.tap(find.text(ptL10n.ctFlagAllTables));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(ptL10n.ctPermissionRead));
        await tester.tap(find.text(ptL10n.ctPermissionRead));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pumpAndSettle();
        expect(find.text('created-secret'), findsOneWidget);
        if (action == 'copy' || action == 'failed-copy') {
          await tester.tap(find.text(ptL10n.ctButtonCopyToken));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          if (action == 'copy') {
            expect(copiedText, 'created-secret');
            final event = audit.events.single;
            expect(event.eventType, TokenAuditEventType.copy);
            expect(event.tokenId, 'token-1');
            expect(event.clientId, provider.secretFeedback!.clientId);
            expect(event.toJson().toString(), isNot(contains('created-secret')));
          } else {
            expect(audit.events, isEmpty);
            expect(find.text(ptL10n.ctInfoClientTokenCopyFailed), findsOneWidget);
          }
        } else {
          final staleCopyCallback = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, ptL10n.ctButtonCopyToken),
              )
              .onPressed!;
          await tester.tap(find.byIcon(action == 'revoke' ? FluentIcons.block_contact : FluentIcons.delete).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(action == 'revoke' ? ptL10n.ctButtonRevoke : ptL10n.ctButtonDelete).last);
          await tester.pumpAndSettle();
          expect(find.text('created-secret'), findsNothing);
          expect(find.text(ptL10n.ctButtonCopyToken), findsNothing);
          expect(provider.lastCreatedToken, isNull);
          staleCopyCallback();
          await tester.pump();
          expect(copiedText, isNull);
          expect(audit.events, isEmpty);
        }
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      });
    }

    for (final change in ['size', 'filter', 'sort']) {
      testWidgets('retry resets scroll after a failed $change change on page one', (tester) async {
        final tokens = List.generate(
          101,
          (index) => ClientTokenSummary(
            id: 'id-$index',
            clientId: 'client-$index',
            createdAt: DateTime.utc(2026),
            isRevoked: false,
            allTables: true,
            allViews: true,
            rules: const [],
          ),
        );
        when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();
        final scroll = tester.widget<ListView>(find.byType(ListView).last).controller!;
        scroll.jumpTo(120);
        await tester.pumpAndSettle();
        when(
          () => mockListClientTokens(query: any(named: 'query')),
        ).thenAnswer((_) async => Failure(domain.DatabaseFailure('injected read failure')));
        switch (change) {
          case 'size':
            tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).onChanged!(100);
          case 'filter':
            await tester.enterText(find.byType(TextBox).first, 'client');
          case 'sort':
            tester.widget<ComboBox<ClientTokenSortOption>>(find.byType(ComboBox<ClientTokenSortOption>)).onChanged!(
              ClientTokenSortOption.oldest,
            );
        }
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(scroll.offset, 120);
        when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
        await tester.tap(find.text(ptL10n.btnRetry));
        await tester.pumpAndSettle();
        expect(provider.currentPage, 1);
        expect(scroll.offset, 0);
        if (change == 'size') expect(provider.pageSize, 100);
      });
    }

    testWidgets('submission does not restore old scroll over a queued filter reset', (tester) async {
      final tokens = List.generate(
        101,
        (index) => ClientTokenSummary(
          id: 'id-$index',
          clientId: 'client-$index',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          rules: const [],
        ),
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      final writing = Completer<Result<ClientTokenCreationResult>>();
      when(() => mockCreateClientToken.createWithIdentity(any())).thenAnswer((_) => writing.future);
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(find.byType(ListView).last).controller!;
      scroll.jumpTo(120);
      await tester.pumpAndSettle();
      final controller = ClientTokenSectionController(settingsStoreLookup: () => null, onSectionChanged: () {});
      addTearDown(controller.dispose);
      controller.allTables = true;
      controller.globalCanRead = true;
      controller.clientIdController.text = 'new';
      final coordinator = ClientTokenSectionCoordinator(controller: controller, scrollController: scroll);
      late BuildContext dialogContext;
      final dialog = showDialog<ClientTokenSubmitFeedback>(
        context: tester.element(find.byType(ClientTokenSection)),
        builder: (context) {
          dialogContext = context;
          return const ContentDialog(title: Text('submission fixture'));
        },
      );
      await tester.pumpAndSettle();
      final submission = coordinator.handleSubmitToken(dialogContext, provider);
      expect(provider.isTokenMutationInProgress, isTrue);
      controller.listClientFilterController.text = 'client';
      final reloading = coordinator.reloadTokensForCurrentFilters(provider);
      writing.complete(const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'created-secret')));
      await tester.pumpAndSettle();
      await submission;
      await reloading;
      expect((await dialog)!.tokenValue, 'created-secret');
      expect(provider.loadedListQuery!.clientIdContains, 'client');
      expect(scroll.offset, 0);
    });

    testWidgets('real corrupt policy remains identifiable and can be revoked and deleted', (tester) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      final repo = ClientTokenRepository(ClientTokenLocalDataSource(db), secretStore: MemoryTokenSecretStore());
      await db.batch(
        (batch) => batch.insertAll(db.clientTokenCacheTable, [
          for (final id in ['good-row', 'bad-row'])
            ClientTokenCacheTableCompanion.insert(
              id: id,
              clientId: id,
              tokenHash: Value('hash-$id'),
              createdAt: DateTime.utc(2026),
              syncedAt: DateTime.utc(2026),
              rulesJson: Value(id == 'bad-row' ? 'invalid JSON' : '[]'),
            ),
        ]),
      );
      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockUpdateClientToken,
        ListClientTokenPage(repo),
        mockGetClientTokenSecret,
        RevokeClientToken(repo),
        DeleteClientToken(repo),
        countActiveClientTokens: CountActiveClientTokens(repo),
      );
      try {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();
        expect(find.text('bad-row'), findsWidgets);
        expect(find.text('good-row'), findsWidgets);
        expect(find.text(ptL10n.ctPolicyInvalidRecovery), findsOneWidget);
        final badActions = find.byWidgetPredicate(
          (widget) => widget is ClientTokenRowActions && widget.token.id == 'bad-row',
        );
        Finder action(IconData icon) =>
            find.descendant(of: badActions, matching: find.widgetWithIcon(IconButton, icon));
        expect(tester.widget<IconButton>(action(FluentIcons.edit)).onPressed, isNull);
        expect(tester.widget<IconButton>(action(FluentIcons.copy)).onPressed, isNull);
        await tester.tap(action(FluentIcons.view));
        await tester.pumpAndSettle();
        expect(find.text(ptL10n.ctPolicyInvalidRecovery), findsNWidgets(2));
        expect(find.text('${ptL10n.ctLabelPayloadAdvanced}:'), findsNothing);
        await tester.tap(find.text(ptL10n.btnOk));
        await tester.pumpAndSettle();
        await tester.tap(action(FluentIcons.block_contact));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ptL10n.ctButtonRevoke));
        await tester.pumpAndSettle();
        expect(provider.tokens.singleWhere((token) => token.id == 'bad-row').isRevoked, isTrue);
        await tester.tap(action(FluentIcons.delete));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ptL10n.ctButtonDelete));
        await tester.pumpAndSettle();
        expect(provider.tokens.single.id, 'good-row');
        expect(find.text(ptL10n.ctPolicyInvalidRecovery), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
        await db.close();
      }
    });

    testWidgets(
      'initial load failure shows inline error and retry instead of empty state',
      (tester) async {
        when(
          () => mockListClientTokens(query: any(named: 'query')),
        ).thenAnswer(
          (_) async => Failure(domain.ValidationFailure('falha ao carregar tokens')),
        );

        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        expect(find.text('falha ao carregar tokens'), findsOneWidget);
        expect(find.text(ptL10n.btnRetry), findsOneWidget);
        expect(find.text(ptL10n.ctMsgNoTokenFound), findsNothing);
      },
    );

    testWidgets('saved create closes form even if refresh fails and retry never creates again', (tester) async {
      when(() => mockCreateClientToken.createWithIdentity(any())).thenAnswer(
        (_) async => const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'created-secret')),
      );
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
      await tester.tap(find.text(ptL10n.ctFlagAllTables));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ptL10n.ctPermissionRead));
      await tester.tap(find.text(ptL10n.ctPermissionRead));
      await tester.pumpAndSettle();
      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => Failure(domain.DatabaseFailure('refresh failed')));
      await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
      await tester.tap(find.text(ptL10n.ctButtonCreateToken));
      await tester.pumpAndSettle();
      expect(find.text(ptL10n.ctDialogCreateTokenTitle), findsNothing);
      expect(find.text(ptL10n.ctSavedListStale), findsOneWidget);
      expect(find.text('created-secret'), findsOneWidget);
      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => const Success(<ClientTokenSummary>[]));
      await tester.tap(find.text(ptL10n.btnRetry));
      await tester.pumpAndSettle();
      expect(find.text(ptL10n.ctSavedListStale), findsNothing);
      verify(() => mockCreateClientToken.createWithIdentity(any())).called(1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('restores controls and queries preferences even with an already loaded provider', (tester) async {
      await provider.loadTokens();
      final store = InMemoryAppSettingsStore({
        ClientTokenListPreferenceKeys.clientFilter: 'saved-client',
        ClientTokenListPreferenceKeys.statusFilter: 'revoked',
        ClientTokenListPreferenceKeys.sortFilter: 'client_asc',
        ClientTokenListPreferenceKeys.pageSize: 100,
        ClientTokenListPreferenceKeys.autoRefreshAfterCreate: false,
      });
      getIt.registerSingleton<IAppSettingsStore>(store);
      addTearDown(() => getIt.unregister<IAppSettingsStore>());
      clearInteractions(mockListClientTokens);
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      expect(tester.widget<TextBox>(find.byType(TextBox).first).controller!.text, 'saved-client');
      expect(find.text(ptL10n.ctFilterStatusRevoked), findsOneWidget);
      expect(find.text(ptL10n.ctSortClientAsc), findsOneWidget);
      expect(find.text(ptL10n.ctButtonAutoRefreshOff), findsOneWidget);
      final query =
          verify(() => mockListClientTokens(query: captureAny(named: 'query'))).captured.single as ClientTokenListQuery;
      expect(query.clientIdContains, 'saved-client');
      expect(query.status, ClientTokenStatusFilter.revoked);
      expect(query.sort, ClientTokenSortOption.clientAsc);
      expect(query.page, 1);
      expect(query.pageSize, 100);
    });

    testWidgets('preference failure warns but still queries the selected filter once', (tester) async {
      final store = _FailingSettingsStore();
      getIt.registerSingleton<IAppSettingsStore>(store);
      addTearDown(() => getIt.unregister<IAppSettingsStore>());
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      clearInteractions(mockListClientTokens);
      await tester.enterText(find.byType(TextBox).first, 'selected-client');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(ptL10n.ctPreferencesSaveFailed), findsOneWidget);
      final query =
          verify(() => mockListClientTokens(query: captureAny(named: 'query'))).captured.single as ClientTokenListQuery;
      expect(query.clientIdContains, 'selected-client');
      expect(store.batches, 1);
    });

    testWidgets('next page and page size issue bounded queries and reset the page', (tester) async {
      final tokens = List.generate(
        101,
        (index) => ClientTokenSummary(
          id: 'id-$index',
          clientId: 'client-$index',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          rules: const [],
        ),
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      expect(provider.tokens, hasLength(50));
      final scroll = tester.widget<ListView>(find.byType(ListView).last).controller!;
      scroll.jumpTo(120);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ptL10n.ctButtonRefreshList));
      await tester.pumpAndSettle();
      expect(scroll.offset, 120);
      await tester.tap(find.text(ptL10n.queryPaginationNext));
      await tester.pumpAndSettle();
      expect(provider.currentPage, 2);
      expect(scroll.offset, 0);
      expect(provider.tokens.first.id, 'id-50');
      final sizePicker = tester.widget<ComboBox<int>>(find.byType(ComboBox<int>));
      sizePicker.onChanged!(25);
      await tester.pumpAndSettle();
      expect(provider.currentPage, 1);
      expect(provider.tokens, hasLength(25));
      expect(provider.totalCount, 101);
      expect(provider.tokens.first.id, 'id-0');
    });

    testWidgets('failed page-size query keeps the confirmed pager and retries page one', (tester) async {
      final tokens = List.generate(
        101,
        (index) => ClientTokenSummary(
          id: 'id-$index',
          clientId: 'client-$index',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          rules: const [],
        ),
      );
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      for (var page = 1; page < 3; page++) {
        await tester.tap(find.text(ptL10n.queryPaginationNext));
        await tester.pumpAndSettle();
      }
      when(
        () => mockListClientTokens(query: any(named: 'query')),
      ).thenAnswer((_) async => Failure(domain.DatabaseFailure('injected read failure')));
      tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).onChanged!(100);
      await tester.pumpAndSettle();
      expect(provider.currentPage, 3);
      expect(provider.pageSize, 50);
      expect(tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).value, 50);
      expect(find.text(ptL10n.ctPaginationSummary(3, 3, 101)), findsOneWidget);
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((_) async => Success(tokens));
      await tester.tap(find.text(ptL10n.btnRetry));
      await tester.pumpAndSettle();
      expect(provider.currentPage, 1);
      expect(provider.pageSize, 100);
      expect(provider.tokens, hasLength(100));
      expect(tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).value, 100);
    });

    testWidgets('debounced filter is applied after a mutation releases admission', (tester) async {
      final token = ClientTokenSummary(
        id: 'id',
        clientId: 'client',
        createdAt: DateTime.utc(2026),
        isRevoked: false,
        allTables: true,
        allViews: true,
        rules: const [],
      );
      final queries = <ClientTokenListQuery>[];
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((invocation) async {
        final query = invocation.namedArguments[#query] as ClientTokenListQuery;
        queries.add(query);
        return Success(query.clientIdContains.isEmpty ? [token] : <ClientTokenSummary>[]);
      });
      final writing = Completer<Result<ClientTokenCreationResult>>();
      when(() => mockCreateClientToken.createWithIdentity(any())).thenAnswer((_) => writing.future);
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).first, 'not-present');
      final mutation = provider.createToken(
        const ClientTokenCreateRequest(
          clientId: 'new',
          allTables: true,
          allViews: true,
          allPermissions: true,
          rules: [],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(provider.isTokenMutationInProgress, isTrue);
      expect(queries, hasLength(1));
      writing.complete(const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'new-secret')));
      await tester.pumpAndSettle();
      expect((await mutation).isSuccess(), isTrue);
      expect(queries.last.clientIdContains, 'not-present');
      expect(provider.tokens, isEmpty);
      expect(provider.currentPage, 1);
    });

    testWidgets('filter debounce and pending query disable navigation until page one is ready', (tester) async {
      final tokens = List.generate(
        101,
        (index) => ClientTokenSummary(
          id: 'id-$index',
          clientId: 'client-$index',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          rules: const [],
        ),
      );
      final filtered = Completer<Result<List<ClientTokenSummary>>>();
      final queries = <ClientTokenListQuery>[];
      when(() => mockListClientTokens(query: any(named: 'query'))).thenAnswer((invocation) {
        final query = invocation.namedArguments[#query] as ClientTokenListQuery;
        queries.add(query);
        return query.clientIdContains.isEmpty ? Future.value(Success(tokens)) : filtered.future;
      });
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ptL10n.queryPaginationNext));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).first, 'client');
      await tester.pump();
      final nextButton = find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == ptL10n.queryPaginationNext,
      );
      expect(tester.widget<AppButton>(nextButton).onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      expect(queries.last.page, 1);
      expect(provider.isQueryPending, isTrue);
      expect(tester.widget<AppButton>(nextButton).onPressed, isNull);
      filtered.complete(Success(tokens));
      await tester.pumpAndSettle();
      expect(provider.currentPage, 1);
      expect(provider.isQueryPending, isFalse);
      expect(tester.widget<AppButton>(nextButton).onPressed, isNotNull);
    });

    testWidgets('slow preference persistence does not delay the selected page-size query', (tester) async {
      final store = _DelayedSettingsStore();
      getIt.registerSingleton<IAppSettingsStore>(store);
      addTearDown(() => getIt.unregister<IAppSettingsStore>());
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();
      tester.widget<ComboBox<int>>(find.byType(ComboBox<int>)).onChanged!(25);
      await tester.pumpAndSettle();
      expect(store.release.isCompleted, isFalse);
      expect(provider.pageSize, 25);
      store.release.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('should add rule and render it in rules grid', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.ctButtonNewToken));
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.ctNoRulesAdded), findsOneWidget);

      await tester.ensureVisible(find.text(ptL10n.ctButtonAddRule));
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

      await tester.ensureVisible(find.text(ptL10n.ctButtonAddRule));
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
      'should show validation error when payload.database is not a string',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        final payloadField = find.byWidgetPredicate((widget) {
          return widget is TextBox && widget.maxLines == 4;
        });
        await tester.enterText(payloadField, '{"database":123}');
        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pumpAndSettle();

        expect(
          find.text(ptL10n.ctErrorPayloadDatabaseMustBeString),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'should require at least one global permission when global scope is enabled',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
        await tester.tap(find.text(ptL10n.ctFlagAllTables));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pumpAndSettle();

        expect(
          find.text(ptL10n.ctErrorGlobalPermissionRequired),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'should hide rule actions in global mode and save without rules',
      (tester) async {
        when(
          () => mockCreateClientToken.createWithIdentity(any()),
        ).thenAnswer((_) async => const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'tok')));

        await tester.binding.setSurfaceSize(const Size(1600, 1200));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctButtonAddRule));
        await tester.tap(find.text(ptL10n.ctButtonAddRule));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextBox).last, 'dbo.clientes');
        await tester.tap(find.text(ptL10n.ctDialogSaveRule));
        await tester.pumpAndSettle();

        expect(find.text('dbo.clientes'), findsOneWidget);
        expect(find.text(ptL10n.ctButtonImportRules), findsOneWidget);
        expect(find.text(ptL10n.ctButtonAddRule), findsOneWidget);

        await tester.tap(find.text(ptL10n.ctFlagAllTables));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ptL10n.ctPermissionRead));
        await tester.pumpAndSettle();

        expect(find.text(ptL10n.ctButtonImportRules), findsNothing);
        expect(find.text(ptL10n.ctButtonAddRule), findsNothing);
        expect(find.text(ptL10n.ctButtonExportRules), findsNothing);
        expect(find.text('dbo.clientes'), findsNothing);
        expect(find.text(ptL10n.ctGlobalScopeRulesDisabled), findsOneWidget);

        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pumpAndSettle();

        final captured =
            verify(
                  () => mockCreateClientToken.createWithIdentity(captureAny()),
                ).captured.single
                as ClientTokenCreateRequest;
        expect(captured.rules, isEmpty);
        expect(captured.globalPermissions.canRead, isTrue);
        expect(captured.globalPermissions.canUpdate, isFalse);
        expect(captured.globalPermissions.canDelete, isFalse);
        expect(captured.globalPermissions.canDdl, isFalse);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'create token dialog lays out without overflow on short viewport',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(920, 640));
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

        await tester.binding.setSurfaceSize(const Size(920, 640));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        final editButton = find.byIcon(FluentIcons.edit).first;
        await tester.ensureVisible(editButton);
        await tester.tap(editButton);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(ptL10n.ctDialogEditTokenTitle), findsOneWidget);
      },
    );

    testWidgets('copy token loads secret on demand', (tester) async {
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
      final secretCompleter = Completer<Result<ClientTokenSecretLookup>>();
      when(
        () => mockGetClientTokenSecret('t1'),
      ).thenAnswer((_) => secretCompleter.future);

      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(FluentIcons.copy).first;
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pump();

      expect(provider.isCopyingTokenSecretFor('t1'), isTrue);
      expect(find.byType(ProgressRing), findsWidgets);

      secretCompleter.complete(
        const Success(
          ClientTokenSecretLookup(tokenValue: 'copied-secret'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => mockGetClientTokenSecret('t1')).called(1);
      expect(find.text(ptL10n.ctInfoClientTokenCopied), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('copy token shows a specific error when secret loading fails', (tester) async {
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
      when(
        () => mockGetClientTokenSecret('t1'),
      ).thenAnswer(
        (_) async => Failure(domain.ServerFailure('storage offline')),
      );

      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      await tester.pumpWidget(_buildWidget(provider));
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(FluentIcons.copy).first;
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => mockGetClientTokenSecret('t1')).called(1);
      expect(find.text(ptL10n.ctInfoClientTokenLoadFailed), findsOneWidget);
      expect(find.textContaining('storage offline'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'list controls stay disabled while revoke is in progress',
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
        final revokeCompleter = Completer<Result<void>>();
        when(
          () => mockListClientTokens(query: any(named: 'query')),
        ).thenAnswer((_) async => Success(<ClientTokenSummary>[token]));
        when(
          () => mockRevokeClientToken('t1'),
        ).thenAnswer((_) => revokeCompleter.future);

        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        final revokeIcon = find.byIcon(FluentIcons.block_contact).first;
        await tester.ensureVisible(revokeIcon);
        await tester.tap(revokeIcon);
        await tester.pumpAndSettle();
        await tester.tap(find.text(ptL10n.ctButtonRevoke).last);
        await tester.pump();

        final newTokenButton = tester.widget<AppButton>(
          find.byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == ptL10n.ctButtonNewToken,
          ),
        );
        final refreshButton = tester.widget<AppButton>(
          find.byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == ptL10n.ctButtonRefreshList,
          ),
        );

        expect(newTokenButton.onPressed, isNull);
        expect(refreshButton.onPressed, isNull);
        expect(find.byType(ProgressRing), findsWidgets);

        revokeCompleter.complete(const Success(unit));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'shows loading indicator while initial token list is loading',
      (tester) async {
        final completer = Completer<Result<List<ClientTokenSummary>>>();
        when(
          () => mockListClientTokens(query: any(named: 'query')),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(_buildWidget(provider));
        await tester.pump();

        expect(find.byType(ProgressRing), findsWidgets);
        expect(find.text(ptL10n.ctMsgNoTokenFound), findsNothing);

        completer.complete(const Success(<ClientTokenSummary>[]));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'token list filters lay out without overflow on narrow width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(820, 900));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(ptL10n.ctButtonClearFilters), findsOneWidget);
      },
    );
    testWidgets('escape closes create token dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
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
        final completer = Completer<Result<ClientTokenCreationResult>>();
        when(
          () => mockCreateClientToken.createWithIdentity(any()),
        ).thenAnswer((_) => completer.future);

        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
        await tester.tap(find.text(ptL10n.ctFlagAllTables));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctPermissionRead));
        await tester.tap(find.text(ptL10n.ctPermissionRead));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctButtonCreateToken));
        await tester.tap(find.text(ptL10n.ctButtonCreateToken));
        await tester.pump();

        final newTokenButton = tester.widget<AppButton>(
          find.byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == ptL10n.ctButtonNewToken,
          ),
        );
        expect(newTokenButton.onPressed, isNull);

        // Simulate a second Enter callback in the same submission cycle.
        final agentBox = tester.widget<TextBox>(
          find.byWidgetPredicate((widget) => widget is TextBox && widget.placeholder == ptL10n.ctHintAgentId),
        );
        agentBox.onSubmitted?.call('agent');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        verify(() => mockCreateClientToken.createWithIdentity(any())).called(1);

        expect(find.text(ptL10n.ctDialogCreateTokenTitle), findsOneWidget);

        completer.complete(const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'new-token')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'agent field done action submits create when form is valid',
      (tester) async {
        when(
          () => mockCreateClientToken.createWithIdentity(any()),
        ).thenAnswer((_) async => const Success(ClientTokenCreationResult(tokenId: 'token-1', tokenValue: 'tok')));

        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        await tester.pumpWidget(_buildWidget(provider));
        await tester.pumpAndSettle();

        await tester.tap(find.text(ptL10n.ctButtonNewToken));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctFlagAllTables));
        await tester.tap(find.text(ptL10n.ctFlagAllTables));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text(ptL10n.ctPermissionRead));
        await tester.tap(find.text(ptL10n.ctPermissionRead));
        await tester.pumpAndSettle();

        final agentField = find.byWidgetPredicate(
          (widget) => widget is TextBox && widget.placeholder == ptL10n.ctHintAgentId,
        );
        await tester.ensureVisible(agentField);
        await tester.tap(agentField);
        await tester.pumpAndSettle();
        await tester.enterText(agentField, 'agent-x');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(() => mockCreateClientToken.createWithIdentity(any())).called(1);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );
  });
}

Widget _buildWidget(ClientTokenProvider provider) {
  return FluentApp(
    locale: const Locale('pt'),
    theme: FluentThemeData(visualDensity: VisualDensity.standard),
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

class _FailingSettingsStore extends InMemoryAppSettingsStore {
  int batches = 0;
  @override
  Future<void> setValues(Map<String, Object> values) async {
    batches++;
    throw Exception('injected preferences failure');
  }
}

class _DelayedSettingsStore extends InMemoryAppSettingsStore {
  final release = Completer<void>();

  @override
  Future<void> setValues(Map<String, Object> values) async {
    await release.future;
    await super.setValues(values);
  }
}

class _RecordingTokenAuditStore implements ITokenAuditStore {
  final events = <TokenAuditEvent>[];
  @override
  Future<void> record(TokenAuditEvent event) async {
    events.add(event);
  }
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_list_filters.dart';

void main() {
  group('ClientTokenListFilters', () {
    late TextEditingController clientFilterController;
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    });

    setUp(() {
      clientFilterController = TextEditingController();
    });

    tearDown(() {
      clientFilterController.dispose();
    });

    testWidgets('renders compact layout without overflow on narrow width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(820, 600));
      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScaffoldPage(
            content: ClientTokenListFilters(
              clientFilterController: clientFilterController,
              tokenStatusFilter: ClientTokenStatusFilter.all,
              tokenSortOption: ClientTokenSortOption.newest,
              isEnabled: true,
              onClientFilterChanged: (_) {},
              statusLabelBuilder: (_) => l10n.ctFilterStatusAll,
              sortLabelBuilder: (_) => l10n.ctSortNewest,
              onStatusChanged: (_) {},
              onSortChanged: (_) {},
              onClearFilters: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.ctButtonClearFilters), findsOneWidget);
    });
  });
}

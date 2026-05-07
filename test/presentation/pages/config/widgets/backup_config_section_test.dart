import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_config_section.dart';

void main() {
  testWidgets('renders section title and diagnostics footnote (EN)', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: BackupConfigSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.configBackupSectionTitle), findsOneWidget);
    expect(find.textContaining('last_restore_error.txt'), findsOneWidget);
    expect(find.text(AppStrings.singleInstanceMessage), findsNothing);
  });

  testWidgets('shows AppStrings single-instance line in Portuguese locale', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: BackupConfigSection(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.singleInstanceMessage), findsOneWidget);
  });
}

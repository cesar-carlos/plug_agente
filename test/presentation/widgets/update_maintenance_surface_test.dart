import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/update_maintenance_surface.dart';

void main() {
  testWidgets('maintenance blocks underlying controls and exposes manual recovery', (tester) async {
    final admission = UpdateMaintenanceAdmission();
    var actions = 0; var reconciles = 0;
    await tester.pumpWidget(FluentApp(locale: const Locale('pt'),
      localizationsDelegates: const [AppLocalizations.delegate, FluentLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
      supportedLocales: const [Locale('pt')],
      home: UpdateMaintenanceSurface(admission: admission,
        reconcile: () async => reconciles++,
        child: Button(onPressed: () => actions++, child: const Text('Alterar configuração')))));
    await tester.tap(find.text('Alterar configuração'));
    expect(actions, 1);
    admission.transition('op', UpdateMaintenancePhase.draining);
    await tester.pumpAndSettle();
    expect(find.text('Manutenção para atualização'), findsOneWidget);
    expect(tester.widget<AbsorbPointer>(find.byKey(const ValueKey('update-maintenance-input'))).absorbing, isTrue);
    admission.transition('op', UpdateMaintenancePhase.dispatchUnknown);
    await tester.pumpAndSettle();
    expect(find.text('Recuperação necessária'), findsOneWidget);
    await tester.tap(find.text('Reconciliar operação'));
    await tester.pumpAndSettle();
    expect(reconciles, 1); expect(actions, 1);
  });
}

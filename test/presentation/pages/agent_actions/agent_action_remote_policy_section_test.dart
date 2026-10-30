import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations_en.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_remote_policy_section.dart';
import 'package:plug_agente/shared/widgets/common/form/app_checkbox.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('keyboard selects faithful mode and requests explicit reapproval in $brightness', (tester) async {
      final l10n = AppLocalizationsEn();
      var faithful = false;
      var reapproval = false;
      var approvals = 0;
      await tester.pumpWidget(
        FluentApp(
          theme: FluentThemeData(brightness: brightness),
          home: ScaffoldPage(
            content: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: AgentActionRemotePolicySection(
                  l10n: l10n,
                  enabled: true,
                  remoteFeatureEnabled: true,
                  remoteAdHocFeatureEnabled: false,
                  remoteEnabled: true,
                  remoteAdHoc: false,
                  remoteFaithfulIo: faithful,
                  faithfulIoEligible: true,
                  remoteApprovalGranted: !reapproval,
                  requiresReapproval: reapproval,
                  reapprovalInfoBarKey: const ValueKey('keyboard-reapproval'),
                  onRemoteEnabledChanged: (_) => approvals++,
                  onRemoteAdHocChanged: (_) => fail('Disabled ad-hoc control was activated.'),
                  onRemoteFaithfulIoChanged: (value) => setState(() {
                    faithful = value;
                    reapproval = true;
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tabTo(tester, find.byKey(const ValueKey('remote-faithful-io')));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(faithful, isTrue);
      expect(approvals, 0);
      expect(find.byKey(const ValueKey('keyboard-reapproval')), findsOneWidget);
      final approve = find.widgetWithText(Button, l10n.agentActionsConfirmRemoteReapprovalConfirm);
      await _tabTo(tester, approve);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(approvals, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('faithful mode respects executor eligibility and exposes reapproval', (tester) async {
    final l10n = AppLocalizationsEn();
    bool? changed;
    var approved = false;
    Future<void> pump(bool eligible) => tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: AgentActionRemotePolicySection(
              l10n: l10n,
              enabled: true,
              remoteFeatureEnabled: true,
              remoteAdHocFeatureEnabled: false,
              remoteEnabled: true,
              remoteAdHoc: false,
              remoteFaithfulIo: false,
              faithfulIoEligible: eligible,
              remoteApprovalGranted: false,
              requiresReapproval: true,
              reapprovalInfoBarKey: const ValueKey('approval'),
              onRemoteEnabledChanged: (value) => approved = value,
              onRemoteAdHocChanged: (_) {},
              onRemoteFaithfulIoChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    await pump(false);
    final control = find.byKey(const ValueKey('remote-faithful-io'));
    expect(tester.widget<AppCheckbox>(control).onChanged, isNull);
    expect(find.text(l10n.agentActionsFaithfulIoUnavailable), findsOneWidget);
    await pump(true);
    expect(tester.widget<AppCheckbox>(control).onChanged, isNotNull);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    await tester.tap(find.text(l10n.agentActionsConfirmRemoteReapprovalConfirm));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  bool hasFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final element = target.evaluate().single;
    var found = identical(context, element);
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) found = true;
      return !found;
    });
    return found;
  }

  for (var attempt = 0; attempt < 20 && !hasFocus(); attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  expect(hasFocus(), isTrue, reason: 'Control must be reachable through keyboard traversal.');
}

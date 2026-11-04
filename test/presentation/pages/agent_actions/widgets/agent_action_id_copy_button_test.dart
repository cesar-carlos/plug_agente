import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_config.dart';
import 'package:plug_agente/domain/actions/action_definition.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_copyable_identifier.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_id_copy_button.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_definition_row.dart';

void main() {
  const actionId = '4f61ae87-9f44-403f-b8fc-714cfd47b3c5';

  testWidgets('copies the action id shown under the name', (tester) async {
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SizedBox(
            height: 40,
            width: 320,
            child: AgentActionDefinitionNameCell(
              definition: const AgentActionDefinition(
                id: actionId,
                name: 'Acao Remota',
                state: AgentActionState.active,
                config: CommandLineActionConfig(command: 'powershell'),
              ),
              l10n: l10n,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey<String>('agent_action_list_copy_id_$actionId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardPayload, actionId);
    expect(find.text(l10n.agentActionsActionIdCopied), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('copies the action id from the labeled command', (tester) async {
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: AgentActionIdCopyButton(
            actionId: actionId,
            l10n: l10n,
            placement: 'detail',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('agent_action_detail_copy_id_$actionId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardPayload, actionId);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('copies a trigger id with its own confirmation', (tester) async {
    const triggerId = '33721785-3441-4e95-ab74-8d9e5ddd54f5';
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: AgentActionIdCopyButton(
            actionId: triggerId,
            l10n: l10n,
            placement: 'trigger',
            tooltip: l10n.agentActionsCopyTriggerId,
            copiedMessage: l10n.agentActionsTriggerIdCopied,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('agent_action_trigger_copy_id_$triggerId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardPayload, triggerId);
    expect(find.text(l10n.agentActionsTriggerIdCopied), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('shows a labeled copy control for a trigger identifier', (tester) async {
    const triggerId = '33721785-3441-4e95-ab74-8d9e5ddd54f5';
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: AgentActionCopyableIdentifier(
            value: triggerId,
            label: l10n.agentActionsTriggerIdLabel,
            placement: 'trigger',
            l10n: l10n,
            copyTooltip: l10n.agentActionsCopyTriggerId,
            copiedMessage: l10n.agentActionsTriggerIdCopied,
          ),
        ),
      ),
    );

    expect(find.text(l10n.agentActionsTriggerIdLabel), findsOneWidget);
    expect(find.text(l10n.agentActionsCopy), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('agent_action_trigger_copy_id_$triggerId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardPayload, triggerId);
    expect(find.text(l10n.agentActionsTriggerIdCopied), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });
}

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_validation.dart';

Future<AppLocalizations> _loadL10n() async {
  const delegate = AppLocalizations.delegate;
  return delegate.load(const Locale('en'));
}

AgentActionDraft _commandLineDraft({String command = 'echo hi', String name = 'Run'}) {
  final draft = AgentActionDraft();
  draft.draftKind = AgentActionDraftKind.commandLine;
  draft.draftType = AgentActionType.commandLine;
  draft.identity.name.text = name;
  draft.commandLine.command.text = command;
  draft.executionPolicy.acceptedExitCodes.text = '0';
  return draft;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentActionDraftValidators.validateBeforeSave', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await _loadL10n();
    });

    test('returns Valid for a happy-path command-line draft', () {
      final draft = _commandLineDraft();
      final result = const AgentActionDraftValidators().validateBeforeSave(
        draft,
        l10n: l10n,
        canSetActive: true,
      );

      expect(result, isA<DraftValidationValid>());
      expect(result.isValid, isTrue);
    });

    test('reports the required-fields branch when the name is empty', () {
      final draft = _commandLineDraft(name: '   ');
      final result = const AgentActionDraftValidators().validateBeforeSave(
        draft,
        l10n: l10n,
        canSetActive: true,
      );

      expect(result, isA<DraftValidationInvalid>());
      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.requiredFields);
      expect(invalid.message, contains(l10n.agentActionsFormName));
    });

    test('flags invalid accepted exit codes', () {
      final draft = _commandLineDraft();
      draft.executionPolicy.acceptedExitCodes.text = 'not-a-number';

      final result = const AgentActionDraftValidators().validateBeforeSave(
        draft,
        l10n: l10n,
        canSetActive: true,
      );

      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.acceptedExitCodes);
      expect(invalid.message, l10n.agentActionsFormInvalidExitCodes);
    });

    test('flags missing remote approval when remote is enabled', () {
      final draft = _commandLineDraft();
      draft.remoteEnabled = true;
      draft.remoteApprovalGranted = false;

      final result = const AgentActionDraftValidators().validateBeforeSave(
        draft,
        l10n: l10n,
        canSetActive: true,
      );

      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.remoteApproval);
    });

    test('flags preflight required when active state is requested but not allowed', () {
      final draft = _commandLineDraft();
      draft.state = AgentActionState.active;

      final result = const AgentActionDraftValidators().validateBeforeSave(
        draft,
        l10n: l10n,
        canSetActive: false,
      );

      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.preflightActiveState);
      expect(invalid.message, l10n.agentActionsPreflightRequiredForActive);
    });
  });

  group('AgentActionDraftValidators.validatePolicies', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await _loadL10n();
    });

    test('returns Valid for a clean draft', () {
      final result = const AgentActionDraftValidators().validatePolicies(
        _commandLineDraft(),
        l10n: l10n,
      );
      expect(result, isA<DraftValidationValid>());
    });

    test('flags an invalid context schema (not a JSON object)', () {
      final draft = _commandLineDraft();
      draft.executionPolicy.runtimeParameterSchema.text = '[1, 2, 3]';

      final result = const AgentActionDraftValidators().validatePolicies(
        draft,
        l10n: l10n,
      );

      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.contextSchema);
    });

    test('flags invalid queue limits when max-concurrent is not a positive int', () {
      final draft = _commandLineDraft();
      draft.executionPolicy.maxConcurrent.text = '-1';

      final result = const AgentActionDraftValidators().validatePolicies(
        draft,
        l10n: l10n,
      );

      final invalid = result as DraftValidationInvalid;
      expect(invalid.field, DraftValidationField.queueLimits);
    });
  });
}

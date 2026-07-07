import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/support/update_check_action_handler.dart';
import 'package:plug_agente/presentation/support/update_support_diagnostics_builder.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:result_dart/result_dart.dart';

class _MockOrchestrator implements IAutoUpdateOrchestrator {
  _MockOrchestrator({
    this.isAvailable = true,
    this.lastManualDiagnostics,
    this.lastAutomaticDiagnostics,
    this.checkManualResult = const Success(ManualCheckOutcome.noUpdate),
    this.checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion),
  }) : hasUpdateAwaitingUserConsent = false;

  @override
  final bool isAvailable;

  @override
  final bool automaticSilentUpdatesEnabled = false;

  @override
  final bool automaticSilentUpdatesAutoApplyEnabled = true;

  @override
  final bool updateNotificationsEnabled = true;

  @override
  final bool hasUpdateAwaitingUserConsent;

  @override
  final bool isSilentCheckInProgress = false;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  Result<ManualCheckOutcome> checkManualResult;
  Result<SilentUpdateOutcome> checkSilentlyResult;

  int checkManualCallCount = 0;
  int checkSilentlyCallCount = 0;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<bool> get hasPendingDownloadedUpdate async => false;

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async {
    checkManualCallCount++;
    return checkManualResult;
  }

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async {
    checkSilentlyCallCount++;
    return checkSilentlyResult;
  }

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async => const Success(unit);

  @override
  Future<Result<void>> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled) async => const Success(unit);

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async => const Success(unit);

  @override
  Future<void> startAutomaticChecks() async {}

  @override
  Future<Result<void>> applyManualOnlyUpdateMode() async => const Success(unit);

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async => const Success(unit);

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async => const Success(unit);

  @override
  Future<void> dispose() async {}
}

UpdateCheckDiagnostics _sampleDiagnostics({
  UpdateCheckCompletionSource? completionSource,
}) {
  return UpdateCheckDiagnostics(
    checkedAt: DateTime(2026, 5, 9, 10, 30),
    configuredFeedUrl: officialAutoUpdateFeedUrl,
    requestedFeedUrl: officialAutoUpdateFeedUrl,
    currentVersion: '1.0.0+1',
    completionSource: completionSource,
  );
}

void main() {
  late AppLocalizations l10n;
  late _MockOrchestrator orchestrator;
  late UpdateCheckActionHandler handler;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    orchestrator = _MockOrchestrator();
    handler = UpdateCheckActionHandler(orchestrator: orchestrator);
  });

  group('UpdateCheckActionHandler', () {
    test('beginManualCheck returns localized checking label', () {
      final start = handler.beginManualCheck(l10n);

      expect(start.checkingLabel, l10n.configUpdatesChecking);
    });

    group('runManualCheck', () {
      test('maps updateAvailable to success dialog', () async {
        orchestrator.checkManualResult = const Success(ManualCheckOutcome.updateAvailable);
        orchestrator.lastManualDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.updateAvailable,
        );

        final completion = await handler.runManualCheck(l10n);

        expect(completion, isA<UpdateCheckManualSuccess>());
        final success = completion as UpdateCheckManualSuccess;
        expect(success.dialogMessage, l10n.configUpdatesAvailable);
        expect(success.dialogType, MessageType.success);
        expect(success.inlineNotice, isNull);
        expect(success.manualCheckDisplayLabel, startsWith(l10n.configLastUpdatePrefix));
        expect(success.diagnosticSections, isNotEmpty);
        expect(orchestrator.checkManualCallCount, 1);
      });

      test('maps noUpdate to inline notice without dialog', () async {
        orchestrator.checkManualResult = const Success(ManualCheckOutcome.noUpdate);
        orchestrator.lastManualDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        );

        final completion = await handler.runManualCheck(l10n);

        expect(completion, isA<UpdateCheckManualSuccess>());
        final success = completion as UpdateCheckManualSuccess;
        expect(success.dialogMessage, isNull);
        expect(success.inlineNotice, isNotNull);
        expect(success.inlineNotice!.message, l10n.configUpdatesNotAvailable);
        expect(success.inlineNotice!.hint, l10n.configUpdatesNotAvailableHint);
        expect(success.inlineNotice!.severity, InfoBarSeverity.success);
        expect(success.manualCheckDisplayLabel, startsWith(l10n.configLastUpdatePrefix));
      });

      test('maps non-success manual outcomes to warning dialog from completion source', () async {
        const outcomes = <ManualCheckOutcome>[
          ManualCheckOutcome.triggerTimeout,
          ManualCheckOutcome.completionTimeout,
          ManualCheckOutcome.circuitOpen,
          ManualCheckOutcome.notInitialized,
          ManualCheckOutcome.disabled,
        ];

        for (final outcome in outcomes) {
          orchestrator = _MockOrchestrator(
            checkManualResult: Success(outcome),
            lastManualDiagnostics: _sampleDiagnostics(
              completionSource: UpdateCheckCompletionSource.triggerTimeout,
            ),
          );
          handler = UpdateCheckActionHandler(orchestrator: orchestrator);

          final completion = await handler.runManualCheck(l10n);

          expect(completion, isA<UpdateCheckManualSuccess>(), reason: '$outcome');
          final success = completion as UpdateCheckManualSuccess;
          expect(success.dialogMessage, l10n.configUpdateCompletionSourceTriggerTimeout);
          expect(success.dialogType, MessageType.warning);
          expect(success.inlineNotice, isNull);
          expect(success.manualCheckDisplayLabel, isEmpty);
        }
      });

      test('maps orchestrator failure to manual failure completion', () async {
        orchestrator.checkManualResult = Failure(
          domain.NetworkFailure.withContext(
            message: 'Unable to reach update server',
            cause: Exception('offline'),
          ),
        );

        final completion = await handler.runManualCheck(l10n);

        expect(completion, isA<UpdateCheckManualFailure>());
        final failure = completion as UpdateCheckManualFailure;
        expect(failure.manualCheckDisplayLabel, isEmpty);
        expect(failure.dialogMessage, 'Unable to reach update server');
        expect(failure.diagnosticSections, isEmpty);
      });
    });

    group('runAutomaticCheck', () {
      test('maps installerReady to warning dialog from completion source', () async {
        orchestrator.checkSilentlyResult = const Success(SilentUpdateOutcome.installerReady);
        orchestrator.lastAutomaticDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.automaticInstallReady,
        );

        final completion = await handler.runAutomaticCheck(l10n);

        expect(completion, isA<UpdateCheckAutomaticSuccess>());
        final success = completion as UpdateCheckAutomaticSuccess;
        expect(success.dialogMessage, l10n.configUpdateCompletionSourceAutomaticInstallReady);
        expect(success.dialogType, MessageType.warning);
        expect(success.inlineNotice, isNull);
      });

      test('maps requiresUserConsent to warning dialog', () async {
        orchestrator.checkSilentlyResult = const Success(SilentUpdateOutcome.requiresUserConsent);
        orchestrator.lastAutomaticDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        );

        final completion = await handler.runAutomaticCheck(l10n);

        expect(completion, isA<UpdateCheckAutomaticSuccess>());
        final success = completion as UpdateCheckAutomaticSuccess;
        expect(success.dialogMessage, l10n.configUpdateCompletionSourceAutomaticAwaitingUserConsent);
        expect(success.dialogType, MessageType.warning);
      });

      test('maps noNewVersion to success inline notice', () async {
        orchestrator.checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion);
        orchestrator.lastAutomaticDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );

        final completion = await handler.runAutomaticCheck(l10n);

        expect(completion, isA<UpdateCheckAutomaticSuccess>());
        final success = completion as UpdateCheckAutomaticSuccess;
        expect(success.dialogMessage, isNull);
        expect(success.inlineNotice, isNotNull);
        expect(success.inlineNotice!.message, l10n.configUpdatesNotAvailable);
        expect(success.inlineNotice!.hint, l10n.configUpdatesNotAvailableHint);
        expect(success.inlineNotice!.severity, InfoBarSeverity.success);
      });

      test('maps skipped automatic outcomes to info inline notice', () async {
        const outcomes = <SilentUpdateOutcome>[
          SilentUpdateOutcome.silentDisabled,
          SilentUpdateOutcome.rolloutSkipped,
          SilentUpdateOutcome.cooldownActive,
          SilentUpdateOutcome.pendingInProgress,
          SilentUpdateOutcome.alreadyInProgress,
          SilentUpdateOutcome.cancelled,
          SilentUpdateOutcome.skippedByQuietHours,
        ];

        for (final outcome in outcomes) {
          orchestrator = _MockOrchestrator(
            checkSilentlyResult: Success(outcome),
            lastAutomaticDiagnostics: _sampleDiagnostics(
              completionSource: UpdateCheckCompletionSource.automaticCooldown,
            ),
          );
          handler = UpdateCheckActionHandler(orchestrator: orchestrator);

          final completion = await handler.runAutomaticCheck(l10n);

          expect(completion, isA<UpdateCheckAutomaticSuccess>(), reason: '$outcome');
          final success = completion as UpdateCheckAutomaticSuccess;
          expect(success.dialogMessage, isNull);
          expect(success.inlineNotice, isNotNull);
          expect(success.inlineNotice!.message, l10n.configUpdateCompletionSourceAutomaticCooldown);
          expect(success.inlineNotice!.severity, InfoBarSeverity.info);
        }
      });

      test('maps orchestrator failure to automatic failure completion', () async {
        orchestrator.checkSilentlyResult = Failure(
          domain.ServerFailure.withContext(
            message: 'Automatic check failed',
            cause: Exception('boom'),
          ),
        );
        orchestrator.lastAutomaticDiagnostics = _sampleDiagnostics(
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        );

        final completion = await handler.runAutomaticCheck(l10n);

        expect(completion, isA<UpdateCheckAutomaticFailure>());
        final failure = completion as UpdateCheckAutomaticFailure;
        expect(failure.dialogMessage, 'Automatic check failed');
        expect(failure.diagnosticSections, isNotEmpty);
      });
    });

    test('buildDiagnosticSections prefers explicit diagnostics over orchestrator state', () {
      final manual = _sampleDiagnostics();
      final background = _sampleDiagnostics(
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
      );
      orchestrator.lastManualDiagnostics = null;
      orchestrator.lastBackgroundDiagnostics = null;

      final sections = handler.buildDiagnosticSections(
        l10n,
        manualDiagnostics: manual,
        backgroundDiagnostics: background,
      );

      expect(sections.length, 2);
      expect(
        sections.first.title,
        l10n.configUpdateTechnicalTitle,
      );
      expect(
        sections.last.title,
        l10n.configUpdateTechnicalBackgroundTitle,
      );
    });

    test('unavailableMessage surfaces resolver output when auto-update is unavailable', () {
      handler = UpdateCheckActionHandler(
        orchestrator: _MockOrchestrator(isAvailable: false),
        capabilities: RuntimeCapabilities.degraded(reasons: const ['test']),
      );

      expect(handler.unavailableMessage(l10n), l10n.configAutoUpdateNotSupported);
    });

    test('buildSupportDiagnosticsText includes version and update diagnostics', () {
      orchestrator.lastManualDiagnostics = _sampleDiagnostics(
        completionSource: UpdateCheckCompletionSource.updateAvailable,
      );

      final text = handler.buildSupportDiagnosticsText(l10n);

      expect(text, contains(handler.appVersion));
      expect(
        text,
        contains(
          UpdateSupportDiagnosticsBuilder.formatCompletionSource(
            l10n,
            UpdateCheckCompletionSource.updateAvailable,
          ),
        ),
      );
    });
  });
}

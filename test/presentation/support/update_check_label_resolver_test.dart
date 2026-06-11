import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/support/update_check_label_resolver.dart';
import 'package:result_dart/result_dart.dart';

class _StubOrchestrator implements IAutoUpdateOrchestrator {
  _StubOrchestrator({
    this.automaticSilentUpdatesEnabled = false,
    this.updateNotificationsEnabled = true,
    this.lastBackgroundDiagnostics,
  }) : hasUpdateAwaitingUserConsent = false;

  @override
  final bool automaticSilentUpdatesEnabled;

  @override
  final bool updateNotificationsEnabled;

  @override
  final bool hasUpdateAwaitingUserConsent;

  @override
  final UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  bool get isAvailable => true;

  @override
  bool get isSilentCheckInProgress => false;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => null;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => null;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<bool> get hasPendingDownloadedUpdate async => false;

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async => throw UnimplementedError();

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async => throw UnimplementedError();

  @override
  Future<void> initialize() async {}

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async => throw UnimplementedError();

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async => throw UnimplementedError();

  @override
  Future<void> startAutomaticChecks() async {}

  @override
  Future<Result<void>> applyManualOnlyUpdateMode() async => throw UnimplementedError();

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async => throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

void main() {
  late AppLocalizations l10n;
  const resolver = UpdateCheckLabelResolver();

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('UpdateCheckLabelResolver', () {
    test('formats checked-at timestamps consistently', () {
      expect(
        UpdateCheckLabelResolver.formatCheckedAt(DateTime(2026, 4, 2, 14, 45)),
        '02/04/2026 14:45',
      );
    });

    test('prefers transient manual label over orchestrator diagnostics', () {
      final label = resolver.lastUpdateCheckLabel(
        l10n: l10n,
        manualCheckDisplayLabel: 'Checking…',
        lastManualDiagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 4, 2, 14, 45),
          configuredFeedUrl: officialAutoUpdateFeedUrl,
          requestedFeedUrl: officialAutoUpdateFeedUrl,
          currentVersion: '1.0.0+1',
        ),
        lastBackgroundDiagnostics: null,
      );

      expect(label, 'Checking…');
    });

    test('picks latest manual or background diagnostics for last check label', () {
      final label = resolver.lastUpdateCheckLabel(
        l10n: l10n,
        manualCheckDisplayLabel: '',
        lastManualDiagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 4, 2, 14, 45),
          configuredFeedUrl: officialAutoUpdateFeedUrl,
          requestedFeedUrl: officialAutoUpdateFeedUrl,
          currentVersion: '1.0.0+1',
        ),
        lastBackgroundDiagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 5, 9, 10, 30),
          configuredFeedUrl: officialAutoUpdateFeedUrl,
          requestedFeedUrl: officialAutoUpdateFeedUrl,
          currentVersion: '1.0.0+1',
        ),
      );

      expect(label, '${l10n.configLastUpdatePrefix}09/05/2026 10:30');
    });

    test('hides background label when automatic silent updates are enabled', () {
      final orchestrator = _StubOrchestrator(
        automaticSilentUpdatesEnabled: true,
        lastBackgroundDiagnostics: UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 5, 8, 9, 15),
          configuredFeedUrl: officialAutoUpdateFeedUrl,
          requestedFeedUrl: officialAutoUpdateFeedUrl,
          currentVersion: '1.0.0+1',
        ),
      );

      expect(
        resolver.lastBackgroundUpdateLabel(l10n: l10n, orchestrator: orchestrator),
        isEmpty,
      );
    });

    test('surfaces pending ready notice when notifications are disabled', () {
      final orchestrator = _StubOrchestrator(
        updateNotificationsEnabled: false,
      );

      expect(
        resolver.pendingUpdateNotice(
          l10n: l10n,
          orchestrator: orchestrator,
          hasPendingDownloadedUpdate: true,
        ),
        l10n.configUpdatePendingReadyNotice,
      );
    });

    test('returns unsupported message when runtime lacks auto-update capability', () {
      expect(
        resolver.autoUpdateUnavailableMessage(
          l10n: l10n,
          isAutoUpdateAvailable: false,
          capabilities: RuntimeCapabilities.degraded(reasons: const ['test']),
        ),
        l10n.configAutoUpdateNotSupported,
      );
    });
  });
}

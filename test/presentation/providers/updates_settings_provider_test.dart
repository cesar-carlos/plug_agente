import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:result_dart/result_dart.dart';

class _FakeOrchestrator implements IAutoUpdateOrchestrator {
  _FakeOrchestrator({
    this.automaticSilentUpdatesEnabled = true,
    this.updateNotificationsEnabled = true,
    this.lastManualDiagnostics,
    this.lastBackgroundDiagnostics,
  });

  @override
  final bool isAvailable = true;

  @override
  bool automaticSilentUpdatesEnabled;

  @override
  bool automaticSilentUpdatesAutoApplyEnabled = true;

  @override
  bool updateNotificationsEnabled;

  @override
  bool isSilentCheckInProgress = false;

  @override
  bool hasUpdateAwaitingUserConsent = false;

  bool hasPendingDownloadedUpdateValue = false;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  final _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => hasPendingDownloadedUpdateValue;

  void emitChange() {
    _changesController.add(null);
  }

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async => const Success(ManualCheckOutcome.noUpdate);

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async => const Success(SilentUpdateOutcome.noNewVersion);

  @override
  Future<void> initialize() async {}

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    automaticSilentUpdatesEnabled = enabled;
    return const Success(unit);
  }

  @override
  Future<Result<void>> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled) async {
    automaticSilentUpdatesAutoApplyEnabled = enabled;
    return const Success(unit);
  }

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async {
    updateNotificationsEnabled = enabled;
    return const Success(unit);
  }

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

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('notifies listeners on every orchestrator change', () async {
    final orchestrator = _FakeOrchestrator(
      automaticSilentUpdatesEnabled: false,
      lastBackgroundDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 8, 9, 15),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.0.0+1',
      ),
    );
    final provider = UpdatesSettingsProvider(
      orchestrator,
      capabilities: RuntimeCapabilities.full(),
    );
    addTearDown(provider.dispose);

    var notifications = 0;
    provider.addListener(() => notifications += 1);
    await Future<void>.delayed(Duration.zero);

    orchestrator.lastBackgroundDiagnostics = UpdateCheckDiagnostics(
      checkedAt: DateTime(2026, 5, 9, 10, 30),
      configuredFeedUrl: officialAutoUpdateFeedUrl,
      requestedFeedUrl: officialAutoUpdateFeedUrl,
      currentVersion: '1.0.0+1',
    );
    orchestrator.emitChange();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, greaterThanOrEqualTo(2));
    expect(
      provider.lastBackgroundUpdateLabel(l10n),
      contains('09/05/2026 10:30'),
    );
  });

  test('refreshes pending notice when staged update appears', () async {
    final orchestrator = _FakeOrchestrator(
      updateNotificationsEnabled: false,
    );
    final provider = UpdatesSettingsProvider(orchestrator);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(provider.pendingUpdateNotice(l10n), isNull);

    orchestrator.hasPendingDownloadedUpdateValue = true;
    orchestrator.emitChange();
    await Future<void>.delayed(Duration.zero);

    expect(provider.hasPendingDownloadedUpdate, isTrue);
    expect(provider.pendingUpdateNotice(l10n), l10n.configUpdatePendingReadyNotice);
  });

  test('hides background label when automatic silent updates are enabled', () {
    final orchestrator = _FakeOrchestrator(
      lastBackgroundDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 8, 9, 15),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.0.0+1',
      ),
    );
    final provider = UpdatesSettingsProvider(orchestrator);
    addTearDown(provider.dispose);

    expect(provider.lastBackgroundUpdateLabel(l10n), isEmpty);
  });

  test('resolves last manual check from orchestrator diagnostics', () {
    final orchestrator = _FakeOrchestrator(
      lastManualDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 4, 2, 14, 45),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.0.0+1',
      ),
    );
    final provider = UpdatesSettingsProvider(orchestrator);
    addTearDown(provider.dispose);

    expect(
      provider.lastUpdateCheckLabel(l10n),
      '${l10n.configLastUpdatePrefix}02/04/2026 14:45',
    );
  });
}

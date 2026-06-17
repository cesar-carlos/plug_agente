import 'dart:ui' show VoidCallback;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/degraded_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update_reconciler.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_automatic_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_cancellation_handler.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_diagnostics_notifier.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_diagnostics_store.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_download_apply_service.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_probe_pipeline.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_rollout_bucket_resolver.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_scheduler.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_uac_guard.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Wires the silent-update collaborators so the coordinator stays an orchestrator.
class SilentUpdateCollaborators {
  SilentUpdateCollaborators._({
    required this.preferences,
    required this.automaticFailureBreaker,
    required this.pendingStore,
    required this.diagnosticsStore,
    required this.scheduler,
    required this.probePipeline,
    required this.downloadApplyService,
    required this.pendingReconciler,
    required this.rolloutBucketResolver,
    required this.cancellationHandler,
    required this.uacGuard,
    required this.checkIdRecorder,
    required this.uacDetector,
    required this.launcherStatusReader,
    required this.clock,
    required this.diagnosticsNotifier,
  });

  factory SilentUpdateCollaborators.create({
    required RuntimeCapabilities capabilities,
    required String? Function() feedUrlResolver,
    IAppcastProbeService? appcastProbeService,
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    IUpdatePreferencesRepository? updatePreferencesRepository,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    VoidCallback? onDiagnosticsChanged,
    int automaticFailureCooldownThreshold = AutoUpdateDefaults.automaticFailureCooldownThreshold,
    Duration automaticFailureCooldown = AutoUpdateDefaults.automaticFailureCooldown,
    Duration helperWaitDuration = AutoUpdateDefaults.helperWaitDuration,
    Duration Function()? bootJitterProvider,
    IAppcastSignatureVerifier? signatureVerifier,
    UpdateCheckIdRecorder? checkIdRecorder,
    IAutoUpdateMetricsCollector? metricsCollector,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
    IUacDetector? uacDetector,
    IPendingSilentUpdateStore? pendingStore,
    ISilentUpdateLauncherStatusReader? launcherStatusReader,
    SilentUpdateDiagnosticsStore? diagnosticsStore,
    SilentUpdateScheduler? scheduler,
    SilentUpdateDownloadApplyService? downloadApplyService,
    PendingSilentUpdateReconciler? pendingReconciler,
    DateTime Function()? clock,
  }) {
    final resolvedClock = clock ?? DateTime.now;
    final appcastProbe = appcastProbeService ?? AppcastProbeService();
    final preferences =
        updatePreferencesRepository ??
        (settingsStore != null ? UpdatePreferencesRepository(settingsStore: settingsStore) : null);
    final wiredPreferences = preferences ?? DegradedUpdatePreferencesRepository();
    final automaticFailureBreaker = createSilentUpdateAutomaticFailureBreaker(
      preferences: wiredPreferences,
      threshold: automaticFailureCooldownThreshold,
      cooldown: automaticFailureCooldown,
      clock: clock,
    );
    final resolvedPendingStore =
        pendingStore ??
        (preferences != null
            ? SettingsBackedPendingSilentUpdateStore(preferences: preferences)
            : InMemoryPendingSilentUpdateStore());
    final resolvedDiagnosticsStore =
        diagnosticsStore ??
        SilentUpdateDiagnosticsStore(
          preferences: wiredPreferences,
        );
    final resolvedScheduler =
        scheduler ??
        SilentUpdateScheduler(
          automaticFailureBreaker: automaticFailureBreaker,
          bootJitterProvider: bootJitterProvider,
          clock: clock,
        );
    final resolvedSignatureVerifier = signatureVerifier ?? Ed25519AppcastSignatureVerifier();
    final resolvedUacDetector = uacDetector ?? const NoopUacDetector();
    final resolvedLauncherStatusReader = launcherStatusReader ?? const NoopSilentUpdateLauncherStatusReader();
    final resolvedCheckIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore);
    final resolvedProbePipeline = SilentUpdateProbePipeline(
      appcastProbeService: appcastProbe,
      signatureVerifier: resolvedSignatureVerifier,
      uacDetector: resolvedUacDetector,
      pendingStore: resolvedPendingStore,
      automaticFailureBreaker: automaticFailureBreaker,
      metricsCollector: metricsCollector,
      clock: resolvedClock,
    );
    final resolvedDownloadApplyService =
        downloadApplyService ??
        SilentUpdateDownloadApplyService(
          installer: silentUpdateInstaller,
          pendingStore: resolvedPendingStore,
          automaticFailureBreaker: automaticFailureBreaker,
          launcherStatusReader: resolvedLauncherStatusReader,
          preferences: preferences,
          metricsCollector: metricsCollector,
          closeApplicationForSilentUpdate: closeApplicationForSilentUpdate,
          clock: resolvedClock,
        );
    final resolvedPendingReconciler =
        pendingReconciler ??
        PendingSilentUpdateReconciler(
          pendingStore: resolvedPendingStore,
          launcherStatusReader: resolvedLauncherStatusReader,
          automaticFailureBreaker: automaticFailureBreaker,
          feedUrlResolver: feedUrlResolver,
          checkIdRecorder: resolvedCheckIdRecorder,
          helperWaitDuration: helperWaitDuration,
          clock: resolvedClock,
        );
    final diagnosticsNotifier = SilentUpdateDiagnosticsNotifier(
      getDiagnostics: () => resolvedDiagnosticsStore.lastAutomaticDiagnostics,
      onDiagnosticsChanged: onDiagnosticsChanged,
      diagnosticsGateway: diagnosticsGateway,
    );
    return SilentUpdateCollaborators._(
      preferences: wiredPreferences,
      automaticFailureBreaker: automaticFailureBreaker,
      pendingStore: resolvedPendingStore,
      diagnosticsStore: resolvedDiagnosticsStore,
      scheduler: resolvedScheduler,
      probePipeline: resolvedProbePipeline,
      downloadApplyService: resolvedDownloadApplyService,
      pendingReconciler: resolvedPendingReconciler,
      rolloutBucketResolver: SilentUpdateRolloutBucketResolver(preferences: preferences),
      cancellationHandler: SilentUpdateCancellationHandler(
        pendingStore: resolvedPendingStore,
        automaticFailureBreaker: automaticFailureBreaker,
        clock: resolvedClock,
      ),
      uacGuard: SilentUpdateUacGuard(
        capabilities: capabilities,
        uacDetector: resolvedUacDetector,
      ),
      checkIdRecorder: resolvedCheckIdRecorder,
      uacDetector: resolvedUacDetector,
      launcherStatusReader: resolvedLauncherStatusReader,
      clock: resolvedClock,
      diagnosticsNotifier: diagnosticsNotifier,
    );
  }

  final IUpdatePreferencesRepository preferences;
  final PersistentCircuitBreaker automaticFailureBreaker;
  final IPendingSilentUpdateStore pendingStore;
  final SilentUpdateDiagnosticsStore diagnosticsStore;
  final SilentUpdateScheduler scheduler;
  final SilentUpdateProbePipeline probePipeline;
  final SilentUpdateDownloadApplyService downloadApplyService;
  final PendingSilentUpdateReconciler pendingReconciler;
  final SilentUpdateRolloutBucketResolver rolloutBucketResolver;
  final SilentUpdateCancellationHandler cancellationHandler;
  final SilentUpdateUacGuard uacGuard;
  final UpdateCheckIdRecorder checkIdRecorder;
  final IUacDetector uacDetector;
  final ISilentUpdateLauncherStatusReader launcherStatusReader;
  final DateTime Function() clock;
  final SilentUpdateDiagnosticsNotifier diagnosticsNotifier;
}

import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_updater_gateway.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/updater_event.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:result_dart/result_dart.dart';

class FakeAutoUpdaterGateway implements IAutoUpdaterGateway {
  UpdaterListener? listener;
  final List<String> feedUrls = <String>[];
  int? interval;
  bool? lastInBackground;
  Exception? checkError;
  Exception? setFeedError;
  Future<void> Function()? onCheckForUpdates;
  final StreamController<UpdaterEvent> _eventsController = StreamController<UpdaterEvent>.broadcast();

  @override
  Stream<UpdaterEvent> get events => _eventsController.stream;

  Future<void> emit(UpdaterEvent event) async {
    _eventsController.add(event);
    await Future<void>.delayed(Duration.zero);
  }

  bool get hasEventSubscribers => _eventsController.hasListener;

  @override
  void addListener(UpdaterListener listener) {
    this.listener = listener;
  }

  @override
  Future<void> setFeedURL(String feedUrl) async {
    if (setFeedError != null) {
      throw setFeedError!;
    }
    feedUrls.add(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) async {
    lastInBackground = inBackground;
    if (checkError != null) {
      throw checkError!;
    }
    if (onCheckForUpdates != null) {
      await onCheckForUpdates!.call();
    }
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {
    this.interval = interval;
  }
}

class FakeAppcastProbeService implements IAppcastProbeService {
  AppcastProbeResult result = const AppcastProbeResult(
    requestUrl: 'https://example.com/appcast.xml',
    latestVersion: '99.0.0+1',
    assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
    assetSize: 5,
    assetName: 'PlugAgente-Setup-99.0.0.exe',
    sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    os: 'windows',
    channel: 'stable',
    rolloutPercentage: 100,
    itemCount: 1,
  );
  String? lastProbeUrl;
  int callCount = 0;

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    callCount++;
    lastProbeUrl = feedUrl;
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: result.latestVersion,
      assetUrl: result.assetUrl,
      assetSize: result.assetSize,
      assetName: result.assetName,
      sha256: result.sha256,
      os: result.os,
      channel: result.channel,
      rolloutPercentage: result.rolloutPercentage,
      itemCount: result.itemCount,
      errorMessage: result.errorMessage,
      edSignature: result.edSignature,
      releaseNotes: result.releaseNotes,
      releaseNotesUrl: result.releaseNotesUrl,
    );
  }
}

class FakeSilentUpdateInstaller implements ISilentUpdateInstaller {
  SilentUpdateInstallRequest? request;
  Result<SilentUpdateInstallResult> result = const Success(
    SilentUpdateInstallResult(
      installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
      logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
      launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
      launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
      installDirectory: r'C:\PlugAgente',
      strategy: SilentUpdateInstallStrategy.currentUserThenElevated,
      installDirectoryWritable: true,
      appPid: 1234,
      updateDirectorySecurityStatus: 'restricted',
    ),
  );
  int cleanupCount = 0;
  int installCount = 0;
  int launchHelperCount = 0;
  SilentUpdateLaunchRequest? lastLaunchRequest;
  Result<void> launchResult = const Success(unit);
  Future<void> Function()? onBeforeReturn;

  /// Lets tests hold `launchPreparedHelper` mid-flight (e.g. to simulate a
  /// second concurrent `applyPendingDownloadedUpdate` call arriving before
  /// the first one's `await` resolves).
  Future<void> Function()? onBeforeLaunchReturn;

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    installCount++;
    this.request = request;
    if (onBeforeReturn != null) {
      await onBeforeReturn!.call();
    }
    return result;
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) async {
    launchHelperCount++;
    lastLaunchRequest = request;
    if (onBeforeLaunchReturn != null) {
      await onBeforeLaunchReturn!.call();
    }
    return launchResult;
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    cleanupCount++;
    return const Success(unit);
  }
}

class FakeAppcastSignatureVerifier implements IAppcastSignatureVerifier {
  AppcastSignatureVerificationStatus status = AppcastSignatureVerificationStatus.valid;

  @override
  Future<AppcastSignatureVerificationStatus> verifyEnclosure({
    required String canonicalPayload,
    required String? base64Signature,
    required String? base64PublicKey,
  }) async {
    return status;
  }
}

class FakePendingSilentUpdateStore implements IPendingSilentUpdateStore {
  PendingSilentUpdate? pending;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    pending = null;
  }

  @override
  Future<PendingSilentUpdate?> read() async => pending;

  @override
  Future<void> write(PendingSilentUpdate pending) async {
    writeCount++;
    this.pending = pending;
  }
}

class FakeUacDetector implements IUacDetector {
  FakeUacDetector({required this.requiresConsent});

  final bool requiresConsent;
  int callCount = 0;

  @override
  UacDetectionState detect() {
    return UacDetectionState(
      elevationType: requiresConsent ? UacElevationType.limited : UacElevationType.full,
      uacEnabled: requiresConsent,
      requiresConsent: requiresConsent,
    );
  }

  @override
  bool requiresUserConsentForElevation() {
    callCount++;
    return requiresConsent;
  }
}

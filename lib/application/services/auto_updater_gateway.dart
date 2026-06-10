import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/application/services/updater_event.dart';

/// Boundary the application layer uses to talk to WinSparkle. Avoids
/// the orchestrator importing the platform-channel plugin types
/// directly. Tests inject a fake; the production registrar wires the
/// real adapter [AutoUpdaterGateway] backed by `package:auto_updater`.
abstract interface class IAutoUpdaterGateway {
  /// Backward-compatible direct listener subscription. New consumers
  /// should prefer [events] (sealed [UpdaterEvent] stream) instead, so
  /// they do not depend on the plugin's `UpdaterListener` mixin.
  void addListener(UpdaterListener listener);

  /// Broadcast stream of sealed [UpdaterEvent]s translated from the
  /// underlying plugin callbacks. Multiple subscribers are allowed and
  /// the stream lives for the gateway lifetime.
  Stream<UpdaterEvent> get events;

  Future<void> setFeedURL(String feedUrl);
  Future<void> checkForUpdates({required bool inBackground});
  Future<void> setScheduledCheckInterval(int interval);
}

/// Production adapter for WinSparkle. Hides the plugin behind the
/// sealed [UpdaterEvent] surface; the orchestrator subscribes to
/// [events] instead of mixing `UpdaterListener` into its own type.
///
/// The constructor is intentionally cheap (no plugin calls): the
/// translator is only attached to `autoUpdater` on the first access to
/// [events]. That keeps test/non-Windows code paths that build the
/// orchestrator (e.g. degraded runtime checks) free from platform
/// channel errors.
class AutoUpdaterGateway implements IAutoUpdaterGateway {
  AutoUpdaterGateway();

  _UpdaterEventTranslator? _translator;

  @override
  void addListener(UpdaterListener listener) {
    autoUpdater.addListener(listener);
  }

  @override
  Stream<UpdaterEvent> get events {
    final existing = _translator;
    if (existing != null) return existing.events;
    final translator = _UpdaterEventTranslator();
    autoUpdater.addListener(translator);
    _translator = translator;
    return translator.events;
  }

  @override
  Future<void> setFeedURL(String feedUrl) {
    return autoUpdater.setFeedURL(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) {
    return autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) {
    return autoUpdater.setScheduledCheckInterval(interval);
  }
}

/// Internal adapter that implements the plugin's `UpdaterListener` and
/// forwards each callback as a sealed [UpdaterEvent] through a broadcast
/// stream.
class _UpdaterEventTranslator with UpdaterListener {
  final StreamController<UpdaterEvent> _controller = StreamController<UpdaterEvent>.broadcast();

  Stream<UpdaterEvent> get events => _controller.stream;

  @override
  void onUpdaterError(UpdaterError? error) {
    _controller.add(UpdaterErrorEvent(message: error?.toString()));
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _controller.add(UpdaterCheckingForUpdate(itemCount: appcast?.items.length));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _controller.add(
      UpdaterUpdateAvailable(
        version: appcastItem?.versionString,
        displayVersion: appcastItem?.displayVersionString,
      ),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _controller.add(UpdaterUpdateNotAvailable(errorMessage: error?.message));
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _controller.add(UpdaterUpdateDownloaded(version: appcastItem?.versionString));
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    _controller.add(UpdaterBeforeQuitForUpdate(version: appcastItem?.versionString));
  }
}

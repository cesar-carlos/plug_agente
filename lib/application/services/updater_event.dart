/// Domain-flavoured replacement for the raw `UpdaterListener` callbacks
/// shipped by `package:auto_updater`. Lets the application layer talk
/// about updater events without importing the platform-channel plugin
/// directly (which is infrastructure-shaped).
///
/// The aggregator (the production `AutoUpdaterGateway` lives in
/// `auto_update_orchestrator.dart`) listens to the plugin and translates
/// each callback into one of these variants. Consumers pattern-match on
/// the sealed type, getting both static exhaustiveness checks and a
/// clean boundary from the underlying SDK.
sealed class UpdaterEvent {
  const UpdaterEvent();
}

/// The updater started the appcast probe / "checking for updates" phase.
/// Carries the number of items the parser observed, for log breadcrumbs.
final class UpdaterCheckingForUpdate extends UpdaterEvent {
  const UpdaterCheckingForUpdate({this.itemCount});
  final int? itemCount;
}

/// The updater concluded that a newer version exists. The fields mirror
/// `AppcastItem` but use plain Dart strings so the application layer
/// does not depend on the plugin types.
final class UpdaterUpdateAvailable extends UpdaterEvent {
  const UpdaterUpdateAvailable({
    this.version,
    this.displayVersion,
  });
  final String? version;
  final String? displayVersion;
}

/// The updater concluded that no newer version is available, or the
/// `up-to-date` response carried a soft error.
final class UpdaterUpdateNotAvailable extends UpdaterEvent {
  const UpdaterUpdateNotAvailable({this.errorMessage});
  final String? errorMessage;
}

/// The updater finished downloading the installer. Mostly informative —
/// the silent flow does not own this transition because it uses its own
/// HTTP downloader.
final class UpdaterUpdateDownloaded extends UpdaterEvent {
  const UpdaterUpdateDownloaded({this.version});
  final String? version;
}

/// The updater is about to quit the host process so the installer can
/// run. The application layer uses this to release any "prevent close"
/// guard before the platform binary terminates the app.
final class UpdaterBeforeQuitForUpdate extends UpdaterEvent {
  const UpdaterBeforeQuitForUpdate({this.version});
  final String? version;
}

/// The updater reported a failure on any of the above transitions. The
/// raw message is preserved verbatim so operators have full context.
/// Suffixed `Event` so it does not collide with the plugin's
/// `UpdaterError` type when both packages are imported side by side.
final class UpdaterErrorEvent extends UpdaterEvent {
  const UpdaterErrorEvent({this.message});
  final String? message;
}

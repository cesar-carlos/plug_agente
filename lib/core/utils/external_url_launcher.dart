import 'dart:io';

/// Opens an HTTP(S) URL in the user's default browser on desktop platforms.
class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static Future<bool> Function(String url) launchCallback = _launchDefault;

  static Future<bool> launch(String url) {
    if (!looksLikeHttpUrl(url)) {
      return Future<bool>.value(false);
    }

    return launchCallback(url);
  }

  static bool looksLikeHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) {
      return false;
    }

    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static Future<bool> _launchDefault(String url) async {
    final trimmedUrl = url.trim();
    if (!looksLikeHttpUrl(trimmedUrl)) {
      return false;
    }

    if (!Platform.isWindows) {
      return false;
    }

    final result = await Process.run(
      'cmd',
      <String>['/c', 'start', '', trimmedUrl],
      runInShell: true,
    );
    return result.exitCode == 0;
  }
}

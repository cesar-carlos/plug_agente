import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/external_url_launcher.dart';

void main() {
  final defaultLaunchCallback = ExternalUrlLauncher.launchCallback;

  tearDown(() {
    ExternalUrlLauncher.launchCallback = defaultLaunchCallback;
  });

  test('looksLikeHttpUrl accepts http and https URLs', () {
    expect(ExternalUrlLauncher.looksLikeHttpUrl('https://example.com/appcast.xml'), isTrue);
    expect(ExternalUrlLauncher.looksLikeHttpUrl('http://localhost:8080/feed'), isTrue);
    expect(ExternalUrlLauncher.looksLikeHttpUrl('ftp://example.com'), isFalse);
    expect(ExternalUrlLauncher.looksLikeHttpUrl('not a url'), isFalse);
  });

  test('launch delegates to launchCallback', () async {
    String? launchedUrl;
    ExternalUrlLauncher.launchCallback = (url) async {
      launchedUrl = url;
      return true;
    };

    final launched = await ExternalUrlLauncher.launch('https://example.com/update');

    expect(launched, isTrue);
    expect(launchedUrl, 'https://example.com/update');
  });

  test('launch returns false for non-http URLs', () async {
    var callbackInvoked = false;
    ExternalUrlLauncher.launchCallback = (url) async {
      callbackInvoked = true;
      return true;
    };

    final launched = await ExternalUrlLauncher.launch('file:///tmp/test');

    expect(launched, isFalse);
    expect(callbackInvoked, isFalse);
  });
}

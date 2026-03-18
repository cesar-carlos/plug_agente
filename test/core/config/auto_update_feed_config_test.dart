import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';

void main() {
  group('resolveAutoUpdateFeedUrl', () {
    test('returns value from define when present', () {
      final result = resolveAutoUpdateFeedUrl(
        environment: {
          'AUTO_UPDATE_FEED_URL': 'https://env.example.com/feed.xml',
        },
        fromDefine: 'https://define.example.com/feed.xml',
      );

      expect(result, 'https://define.example.com/feed.xml');
    });

    test('returns value from environment when define is empty', () {
      final result = resolveAutoUpdateFeedUrl(
        environment: {
          'AUTO_UPDATE_FEED_URL': 'https://env.example.com/feed.xml',
        },
        fromDefine: '',
      );

      expect(result, 'https://env.example.com/feed.xml');
    });

    test('returns empty string when no source is configured', () {
      final result = resolveAutoUpdateFeedUrl(
        environment: const {},
        fromDefine: '',
      );

      expect(result, isEmpty);
    });
  });

  group('isSparkleFeedUrl', () {
    test('accepts xml URL with query string', () {
      expect(
        isSparkleFeedUrl('https://example.com/appcast.xml?cache=1'),
        isTrue,
      );
    });

    test('rejects non-xml URL', () {
      expect(isSparkleFeedUrl('https://example.com/check'), isFalse);
    });
  });
}

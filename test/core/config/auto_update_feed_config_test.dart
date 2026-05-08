import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';

void main() {
  group('resolveAutoUpdateFeedOverride', () {
    test('returns null when no source is configured', () {
      final result = resolveAutoUpdateFeedOverride(
        environment: const {},
        fromDefine: '',
      );

      expect(result, isNull);
    });

    test('prefers define over environment', () {
      final result = resolveAutoUpdateFeedOverride(
        environment: {
          'AUTO_UPDATE_FEED_URL': 'https://env.example.com/feed.xml',
        },
        fromDefine: 'https://define.example.com/feed.xml',
      );

      expect(result, 'https://define.example.com/feed.xml');
    });
  });

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

    test('returns official feed when no source is configured', () {
      final result = resolveAutoUpdateFeedUrl(
        environment: const {},
        fromDefine: '',
      );

      expect(result, officialAutoUpdateFeedUrl);
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

  group('isOfficialAutoUpdateFeedUrl', () {
    test('accepts official feed URL with cache-busting query', () {
      expect(
        isOfficialAutoUpdateFeedUrl(
          '$officialAutoUpdateFeedUrl?cb=123',
        ),
        isTrue,
      );
    });

    test('rejects non-official feed URL', () {
      expect(
        isOfficialAutoUpdateFeedUrl('https://example.com/appcast.xml'),
        isFalse,
      );
    });
  });

  group('hasInvalidAutoUpdateFeedOverride', () {
    test('returns false when there is no override', () {
      final result = hasInvalidAutoUpdateFeedOverride(
        environment: const {},
        fromDefine: '',
      );

      expect(result, isFalse);
    });

    test('returns true when override is not xml', () {
      final result = hasInvalidAutoUpdateFeedOverride(
        environment: const {
          'AUTO_UPDATE_FEED_URL': 'https://example.com/check',
        },
      );

      expect(result, isTrue);
    });

    test('returns false when override is a sparkle xml feed', () {
      final result = hasInvalidAutoUpdateFeedOverride(
        environment: const {
          'AUTO_UPDATE_FEED_URL': 'https://example.com/appcast.xml?cb=1',
        },
      );

      expect(result, isFalse);
    });
  });

  group('resolveAutoUpdateCheckIntervalSeconds', () {
    test('returns default when not configured', () {
      final result = resolveAutoUpdateCheckIntervalSeconds(
        environment: const {},
      );

      expect(result, 3600);
    });

    test('returns default when value is below minimum', () {
      final result = resolveAutoUpdateCheckIntervalSeconds(
        environment: const {
          'AUTO_UPDATE_CHECK_INTERVAL_SECONDS': '300',
        },
      );

      expect(result, 3600);
    });

    test('returns configured value when value is valid', () {
      final result = resolveAutoUpdateCheckIntervalSeconds(
        environment: const {
          'AUTO_UPDATE_CHECK_INTERVAL_SECONDS': '7200',
        },
      );

      expect(result, 7200);
    });
  });
}

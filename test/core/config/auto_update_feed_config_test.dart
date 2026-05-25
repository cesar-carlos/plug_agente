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

    test('accepts HTTP loopback xml URL', () {
      expect(isSparkleFeedUrl('http://localhost/appcast.xml'), isTrue);
      expect(isSparkleFeedUrl('http://127.0.0.1:8080/appcast.xml'), isTrue);
      expect(isSparkleFeedUrl('http://[::1]:8080/appcast.xml'), isTrue);
    });

    test('rejects external HTTP xml URL', () {
      expect(isSparkleFeedUrl('http://example.com/appcast.xml'), isFalse);
    });

    test('rejects relative xml URL', () {
      expect(isSparkleFeedUrl('/appcast.xml'), isFalse);
    });

    test('rejects non-xml URL', () {
      expect(isSparkleFeedUrl('https://example.com/check'), isFalse);
    });
  });

  group('isAutoUpdateInstallerUrl', () {
    test('accepts HTTPS exe URL', () {
      expect(
        isAutoUpdateInstallerUrl('https://example.com/PlugAgente-Setup.exe?cache=1'),
        isTrue,
      );
    });

    test('accepts HTTP loopback exe URL', () {
      expect(isAutoUpdateInstallerUrl('http://localhost/PlugAgente-Setup.exe'), isTrue);
      expect(isAutoUpdateInstallerUrl('http://127.0.0.1:8080/PlugAgente-Setup.exe'), isTrue);
      expect(isAutoUpdateInstallerUrl('http://[::1]:8080/PlugAgente-Setup.exe'), isTrue);
    });

    test('rejects external HTTP exe URL', () {
      expect(isAutoUpdateInstallerUrl('http://example.com/PlugAgente-Setup.exe'), isFalse);
    });

    test('rejects relative exe URL', () {
      expect(isAutoUpdateInstallerUrl('PlugAgente-Setup.exe'), isFalse);
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

  group('resolveAutoUpdateDownloadTimeoutSeconds', () {
    test('returns default when not configured', () {
      final result = resolveAutoUpdateDownloadTimeoutSeconds(
        environment: const {},
      );

      expect(result, 300);
    });

    test('returns default when value is below minimum', () {
      final result = resolveAutoUpdateDownloadTimeoutSeconds(
        environment: const {
          'AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS': '30',
        },
      );

      expect(result, 300);
    });

    test('returns default when value is non-numeric', () {
      final result = resolveAutoUpdateDownloadTimeoutSeconds(
        environment: const {
          'AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS': 'fast',
        },
      );

      expect(result, 300);
    });

    test('returns configured value when at minimum boundary', () {
      final result = resolveAutoUpdateDownloadTimeoutSeconds(
        environment: const {
          'AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS': '60',
        },
      );

      expect(result, 60);
    });

    test('returns configured value when above minimum', () {
      final result = resolveAutoUpdateDownloadTimeoutSeconds(
        environment: const {
          'AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS': '600',
        },
      );

      expect(result, 600);
    });
  });

  group('resolveAutoUpdateHelperWaitMinutes', () {
    test('returns default when not configured', () {
      expect(resolveAutoUpdateHelperWaitMinutes(environment: const {}), 30);
    });

    test('returns default when below minimum', () {
      expect(
        resolveAutoUpdateHelperWaitMinutes(
          environment: const {'AUTO_UPDATE_HELPER_WAIT_MINUTES': '2'},
        ),
        30,
      );
    });

    test('returns default when above maximum', () {
      expect(
        resolveAutoUpdateHelperWaitMinutes(
          environment: const {'AUTO_UPDATE_HELPER_WAIT_MINUTES': '200'},
        ),
        30,
      );
    });

    test('returns default when non-numeric', () {
      expect(
        resolveAutoUpdateHelperWaitMinutes(
          environment: const {'AUTO_UPDATE_HELPER_WAIT_MINUTES': 'fast'},
        ),
        30,
      );
    });

    test('returns configured value at minimum boundary', () {
      expect(
        resolveAutoUpdateHelperWaitMinutes(
          environment: const {'AUTO_UPDATE_HELPER_WAIT_MINUTES': '5'},
        ),
        5,
      );
    });

    test('returns configured value at maximum boundary', () {
      expect(
        resolveAutoUpdateHelperWaitMinutes(
          environment: const {'AUTO_UPDATE_HELPER_WAIT_MINUTES': '120'},
        ),
        120,
      );
    });
  });

  group('resolveAutoUpdateRequireValidSignature', () {
    test('returns true when not configured (secure default)', () {
      expect(
        resolveAutoUpdateRequireValidSignature(environment: const {}),
        isTrue,
      );
    });

    test('returns false when explicitly set to false', () {
      for (final value in ['false', '0', 'no', 'nao']) {
        expect(
          resolveAutoUpdateRequireValidSignature(
            environment: {'AUTO_UPDATE_REQUIRE_VALID_SIGNATURE': value},
          ),
          isFalse,
          reason: 'expected false for value="$value"',
        );
      }
    });

    test('returns true when set to true or any non-false value', () {
      for (final value in ['true', '1', 'yes', 'sim']) {
        expect(
          resolveAutoUpdateRequireValidSignature(
            environment: {'AUTO_UPDATE_REQUIRE_VALID_SIGNATURE': value},
          ),
          isTrue,
          reason: 'expected true for value="$value"',
        );
      }
    });
  });
}

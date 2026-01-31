import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';

void main() {
  group('DeepLinkService', () {
    late DeepLinkService service;

    setUp(() {
      service = DeepLinkService();
    });

    group('getInitialLink', () {
      test('should extract plugdb protocol link from args', () {
        final args = ['exe', 'plugdb://config'];
        expect(service.getInitialLink(args), equals('plugdb://config'));
      });

      test('should extract http link from args', () {
        final args = ['exe', 'http://example.com/config'];
        expect(
          service.getInitialLink(args),
          equals('http://example.com/config'),
        );
      });

      test('should extract https link from args', () {
        final args = ['exe', 'https://example.com/playground'];
        expect(
          service.getInitialLink(args),
          equals('https://example.com/playground'),
        );
      });

      test('should return null when no link in args', () {
        final args = ['exe', '--verbose'];
        expect(service.getInitialLink(args), isNull);
      });

      test('should return null for empty args', () {
        expect(service.getInitialLink([]), isNull);
      });

      test('should find first link when multiple present', () {
        final args = [
          'exe',
          'plugdb://dashboard',
          'plugdb://config',
        ];
        expect(service.getInitialLink(args), equals('plugdb://dashboard'));
      });
    });

    group('deepLinkToRoute', () {
      test('should convert dashboard link to route', () {
        expect(service.deepLinkToRoute('plugdb://'), equals('/'));
      });

      test('should convert config link to route', () {
        expect(service.deepLinkToRoute('plugdb://config'), equals('/config'));
      });

      test('should convert config link with ID to route', () {
        expect(
          service.deepLinkToRoute('plugdb://config/abc123'),
          equals('/config/abc123'),
        );
      });

      test('should convert playground link to route', () {
        expect(
          service.deepLinkToRoute('plugdb://playground'),
          equals('/playground'),
        );
      });

      test('should convert link with query parameters', () {
        expect(
          service.deepLinkToRoute('plugdb://config?tab=websocket'),
          equals('/config?tab=websocket'),
        );
      });

      test('should convert link with multiple query parameters', () {
        expect(
          service.deepLinkToRoute('plugdb://playground?id=123&tab=main'),
          equals('/playground?id=123&tab=main'),
        );
      });

      test('should convert http links', () {
        expect(
          service.deepLinkToRoute('http://example.com/config'),
          equals('/config'),
        );
      });

      test('should convert https links', () {
        expect(
          service.deepLinkToRoute('https://example.com/playground'),
          equals('/playground'),
        );
      });

      test('should return null for invalid links', () {
        expect(service.deepLinkToRoute('invalid://link'), isNull);
      });

      test('should return null for malformed links', () {
        expect(service.deepLinkToRoute('not-a-url'), isNull);
      });

      test('should handle empty path in custom protocol', () {
        expect(service.deepLinkToRoute('plugdb://'), equals('/'));
      });
    });

    group('createDeepLink', () {
      test('should create deep link for root route', () {
        expect(
          service.createDeepLink('/'),
          equals('plugdb://'),
        );
      });

      test('should create deep link for config route', () {
        expect(
          service.createDeepLink('/config'),
          equals('plugdb://config'),
        );
      });

      test('should create deep link with query parameters', () {
        expect(
          service.createDeepLink(
            '/config',
            queryParameters: {'tab': 'websocket'},
          ),
          equals('plugdb://config?tab=websocket'),
        );
      });

      test('should create deep link with multiple query parameters', () {
        expect(
          service.createDeepLink(
            '/playground',
            queryParameters: {
              'id': 'abc123',
              'tab': 'main',
            },
          ),
          equals('plugdb://playground?id=abc123&tab=main'),
        );
      });

      test('should create deep link for config with ID', () {
        expect(
          service.createDeepLink('/config/abc123'),
          equals('plugdb://config/abc123'),
        );
      });

      test('should create deep link for config with ID and params', () {
        expect(
          service.createDeepLink(
            '/config/abc123',
            queryParameters: {'tab': 'db'},
          ),
          equals('plugdb://config/abc123?tab=db'),
        );
      });

      test('should handle empty query parameters', () {
        expect(
          service.createDeepLink('/config', queryParameters: {}),
          equals('plugdb://config'),
        );
      });

      test('should create deep link with query parameters', () {
        expect(
          service.createDeepLink(
            '/playground',
            queryParameters: {'q': 'hello world'},
          ),
          equals('plugdb://playground?q=hello world'),
        );
      });
    });

    group('isValidDeepLink', () {
      test('should return true for plugdb protocol', () {
        expect(service.isValidDeepLink('plugdb://config'), isTrue);
      });

      test('should return true for http protocol', () {
        expect(service.isValidDeepLink('http://example.com'), isTrue);
      });

      test('should return true for https protocol', () {
        expect(service.isValidDeepLink('https://example.com'), isTrue);
      });

      test('should return false for other protocols', () {
        expect(service.isValidDeepLink('mailto://test@example.com'), isFalse);
        expect(service.isValidDeepLink('ftp://example.com'), isFalse);
        expect(service.isValidDeepLink('file:///path/to/file'), isFalse);
      });

      test('should return false for null', () {
        expect(service.isValidDeepLink(null), isFalse);
      });

      test('should return false for empty string', () {
        expect(service.isValidDeepLink(''), isFalse);
      });

      test('should return false for malformed URLs', () {
        expect(service.isValidDeepLink('not a url'), isFalse);
        expect(service.isValidDeepLink('plugdb:'), isFalse);
      });
    });

    group('examples', () {
      test('should contain all example links', () {
        expect(DeepLinkService.examples, isNotEmpty);
        expect(DeepLinkService.examples.length, greaterThan(0));
      });

      test('all example links should be valid', () {
        final service = DeepLinkService();
        for (final link in DeepLinkService.examples.values) {
          expect(service.isValidDeepLink(link), isTrue);
        }
      });

      test('example links should be convertable to routes', () {
        final service = DeepLinkService();
        for (final link in DeepLinkService.examples.values) {
          final route = service.deepLinkToRoute(link);
          expect(route, isNotNull);
          expect(route, isNotEmpty);
        }
      });
    });
  });
}

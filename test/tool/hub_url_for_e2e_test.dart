import 'package:test/test.dart';

import '../../tool/src/e2e_hub_login_from_env.dart';
import '../../tool/src/hub_url_for_e2e.dart';

void main() {
  group('ensureAgentsNamespaceUrl', () {
    test('appends /agents to base URL', () {
      expect(
        ensureAgentsNamespaceUrl('https://hub.example.com'),
        'https://hub.example.com/agents',
      );
    });

    test('does not duplicate /agents suffix', () {
      expect(
        ensureAgentsNamespaceUrl('https://hub.example.com/agents'),
        'https://hub.example.com/agents',
      );
    });

    test('replaces /consumers suffix with /agents', () {
      expect(
        ensureAgentsNamespaceUrl('https://hub.example.com/consumers'),
        'https://hub.example.com/agents',
      );
    });
  });

  group('hubHttpLoginServerUrl', () {
    test('should strip agents namespace for HTTP login base URL', () {
      expect(
        hubHttpLoginServerUrl('https://plug-server.example.com/agents'),
        'https://plug-server.example.com',
      );
      expect(
        hubHttpLoginServerUrl('https://plug-server.example.com'),
        'https://plug-server.example.com',
      );
    });
  });

  group('isPlaceholderServerUrl', () {
    test('returns true for empty and example placeholder', () {
      expect(isPlaceholderServerUrl(''), isTrue);
      expect(isPlaceholderServerUrl('https://api.example.com'), isTrue);
    });

    test('returns false for real hub URL', () {
      expect(isPlaceholderServerUrl('https://hub.example.com'), isFalse);
    });
  });
}

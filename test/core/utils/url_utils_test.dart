import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/url_utils.dart';

void main() {
  group('hubHttpBaseUrl', () {
    test('strips /agents suffix for HTTP auth calls', () {
      expect(
        hubHttpBaseUrl('https://hub.example.com/agents'),
        'https://hub.example.com',
      );
    });

    test('strips /consumers suffix for HTTP auth calls', () {
      expect(
        hubHttpBaseUrl('https://hub.example.com/consumers'),
        'https://hub.example.com',
      );
    });

    test('preserves base URL when there is no socket namespace suffix', () {
      expect(
        hubHttpBaseUrl('https://hub.example.com'),
        'https://hub.example.com',
      );
    });
  });

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

    test('preserves query parameters', () {
      expect(
        ensureAgentsNamespaceUrl('https://hub.example.com?env=dev'),
        'https://hub.example.com/agents?env=dev',
      );
    });

    test('replaces /consumers suffix and preserves query parameters', () {
      expect(
        ensureAgentsNamespaceUrl('https://hub.example.com/consumers?env=dev'),
        'https://hub.example.com/agents?env=dev',
      );
    });

    test('supports websocket URLs', () {
      expect(
        ensureAgentsNamespaceUrl('wss://hub.example.com'),
        'wss://hub.example.com/agents',
      );
    });
  });
}

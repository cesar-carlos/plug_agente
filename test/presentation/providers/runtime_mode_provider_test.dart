import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';

void main() {
  group('RuntimeModeProvider', () {
    test('should expose full capabilities', () {
      // Arrange
      final capabilities = RuntimeCapabilities.full();
      final provider = RuntimeModeProvider(capabilities);

      // Assert
      expect(provider.isFullySupported, isTrue);
      expect(provider.isDegraded, isFalse);
      expect(provider.isUnsupported, isFalse);
      expect(provider.supportsTray, isTrue);
      expect(provider.supportsNotifications, isTrue);
      expect(provider.supportsAutoUpdate, isTrue);
      expect(provider.supportsWindowManager, isTrue);
      expect(provider.degradationReasons, isEmpty);
    });

    test('should expose degraded capabilities', () {
      // Arrange
      final capabilities = RuntimeCapabilities.degraded(
        reasons: ['Test reason 1', 'Test reason 2'],
      );
      final provider = RuntimeModeProvider(capabilities);

      // Assert
      expect(provider.isDegraded, isTrue);
      expect(provider.isFullySupported, isFalse);
      expect(provider.supportsTray, isFalse);
      expect(provider.supportsNotifications, isFalse);
      expect(provider.degradationReasons, hasLength(2));
      expect(provider.degradationReasons, contains('Test reason 1'));
    });

    test('should expose unsupported capabilities', () {
      // Arrange
      final capabilities = RuntimeCapabilities.unsupported(
        reasons: ['Unsupported OS'],
      );
      final provider = RuntimeModeProvider(capabilities);

      // Assert
      expect(provider.isUnsupported, isTrue);
      expect(provider.supportsWindowManager, isFalse);
    });

    test('should return original capabilities object', () {
      // Arrange
      final capabilities = RuntimeCapabilities.full();
      final provider = RuntimeModeProvider(capabilities);

      // Assert
      expect(provider.capabilities, same(capabilities));
    });
  });
}

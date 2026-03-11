import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';

void main() {
  group('RuntimePolicyEvaluator', () {
    late RuntimePolicyEvaluator evaluator;

    setUp(() {
      evaluator = const RuntimePolicyEvaluator();
    });

    group('Windows 10/11 Client', () {
      test('should return full capabilities for Windows 10', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 19045,
          isServer: false,
          productName: 'Windows 10',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.mode, RuntimeMode.full);
        expect(capabilities.isFullySupported, isTrue);
        expect(capabilities.supportsTray, isTrue);
        expect(capabilities.supportsNotifications, isTrue);
        expect(capabilities.supportsAutoUpdate, isTrue);
        expect(capabilities.supportsWindowManager, isTrue);
        expect(capabilities.degradationReasons, isEmpty);
      });

      test('should return full capabilities for Windows 11', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 22000,
          isServer: false,
          productName: 'Windows 11',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isFullySupported, isTrue);
        expect(capabilities.mode, RuntimeMode.full);
      });
    });

    group('Windows Server 2012/2012 R2', () {
      test('should return degraded capabilities for Server 2012', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 2,
          buildNumber: 9200,
          isServer: true,
          productName: 'Windows Server 2012',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.mode, RuntimeMode.degraded);
        expect(capabilities.isDegraded, isTrue);
        expect(capabilities.supportsTray, isFalse);
        expect(capabilities.supportsNotifications, isFalse);
        expect(capabilities.supportsAutoUpdate, isFalse);
        expect(capabilities.supportsWindowManager, isTrue);
        expect(capabilities.degradationReasons, isNotEmpty);
        expect(
          capabilities.degradationReasons.any(
            (r) => r.contains('Windows Server 2012'),
          ),
          isTrue,
        );
      });

      test('should return degraded capabilities for Server 2012 R2', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 3,
          buildNumber: 9600,
          isServer: true,
          productName: 'Windows Server 2012 R2',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isDegraded, isTrue);
        expect(capabilities.supportsTray, isFalse);
      });
    });

    group('Windows Server 2016+', () {
      test('should return degraded capabilities for Server 2016+', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 14393,
          isServer: true,
          productName: 'Windows Server 2016',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isDegraded, isTrue);
        expect(capabilities.supportsTray, isFalse);
        expect(capabilities.supportsNotifications, isFalse);
        expect(
          capabilities.degradationReasons.any((r) => r.contains('Server')),
          isTrue,
        );
      });
    });

    group('Windows 8/8.1 Client', () {
      test('should return degraded capabilities for Windows 8', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 2,
          buildNumber: 9200,
          isServer: false,
          productName: 'Windows 8',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isDegraded, isTrue);
        expect(capabilities.canRunCore, isTrue);
      });

      test('should return degraded capabilities for Windows 8.1', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 3,
          buildNumber: 9600,
          isServer: false,
          productName: 'Windows 8.1',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isDegraded, isTrue);
      });
    });

    group('Unsupported Windows versions', () {
      test('should return unsupported for Windows 7', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 1,
          buildNumber: 7601,
          isServer: false,
          productName: 'Windows 7',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.mode, RuntimeMode.unsupported);
        expect(capabilities.isUnsupported, isTrue);
        expect(capabilities.canRunCore, isFalse);
        expect(capabilities.supportsTray, isFalse);
        expect(capabilities.supportsNotifications, isFalse);
        expect(capabilities.supportsAutoUpdate, isFalse);
        expect(capabilities.supportsWindowManager, isFalse);
        expect(
          capabilities.degradationReasons.any(
            (r) => r.contains('mínimo suportado'),
          ),
          isTrue,
        );
      });

      test('should return unsupported for Server 2008 R2', () {
        // Arrange
        const versionInfo = WindowsVersionInfo(
          majorVersion: 6,
          minorVersion: 1,
          buildNumber: 7601,
          isServer: true,
          productName: 'Windows Server 2008 R2',
        );

        // Act
        final capabilities = evaluator.evaluate(versionInfo);

        // Assert
        expect(capabilities.isUnsupported, isTrue);
        expect(capabilities.canRunCore, isFalse);
      });
    });
  });
}

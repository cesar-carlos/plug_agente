import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';

void main() {
  group('WindowsVersionInfo', () {
    test('should identify Windows 10 or later', () {
      // Arrange
      const win10 = WindowsVersionInfo(
        majorVersion: 10,
        minorVersion: 0,
        buildNumber: 19045,
        isServer: false,
      );

      const win11 = WindowsVersionInfo(
        majorVersion: 10,
        minorVersion: 0,
        buildNumber: 22000,
        isServer: false,
      );

      // Assert
      expect(win10.isWindows10OrLater, isTrue);
      expect(win11.isWindows10OrLater, isTrue);
    });

    test('should identify Windows 8 / Server 2012', () {
      // Arrange
      const win8 = WindowsVersionInfo(
        majorVersion: 6,
        minorVersion: 2,
        buildNumber: 9200,
        isServer: false,
      );

      const server2012 = WindowsVersionInfo(
        majorVersion: 6,
        minorVersion: 2,
        buildNumber: 9200,
        isServer: true,
      );

      // Assert
      expect(win8.isWindows8OrServer2012, isTrue);
      expect(server2012.isWindows8OrServer2012, isTrue);
    });

    test('should identify Windows 8.1 / Server 2012 R2', () {
      // Arrange
      const win81 = WindowsVersionInfo(
        majorVersion: 6,
        minorVersion: 3,
        buildNumber: 9600,
        isServer: false,
      );

      // Assert
      expect(win81.isWindows81OrServer2012R2, isTrue);
    });

    test('should identify versions below Windows 8', () {
      // Arrange
      const win7 = WindowsVersionInfo(
        majorVersion: 6,
        minorVersion: 1,
        buildNumber: 7601,
        isServer: false,
      );

      const winVista = WindowsVersionInfo(
        majorVersion: 6,
        minorVersion: 0,
        buildNumber: 6002,
        isServer: false,
      );

      // Assert
      expect(win7.isBelowWindows8, isTrue);
      expect(winVista.isBelowWindows8, isTrue);
    });

    test('should format version string correctly', () {
      // Arrange
      const versionInfo = WindowsVersionInfo(
        majorVersion: 10,
        minorVersion: 0,
        buildNumber: 19045,
        isServer: false,
      );

      // Assert
      expect(versionInfo.versionString, '10.0.19045');
    });

    test('should include product name in toString', () {
      // Arrange
      const versionInfo = WindowsVersionInfo(
        majorVersion: 10,
        minorVersion: 0,
        buildNumber: 22000,
        isServer: false,
        productName: 'Windows 11',
      );

      // Act
      final string = versionInfo.toString();

      // Assert
      expect(string, contains('10.0.22000'));
      expect(string, contains('Windows 11'));
      expect(string, contains('isServer: false'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/path_extension.dart';

void main() {
  group('extensionOf', () {
    test('should return lowercase extension from file path', () {
      expect(extensionOf(r'C:\Tools\job.EXE'), '.exe');
      expect(extensionOf('backup.ps1'), '.ps1');
    });

    test('should return null for paths without extension', () {
      expect(extensionOf(r'C:\Tools\README'), isNull);
      expect(extensionOf(null), isNull);
      expect(extensionOf('file.'), isNull);
    });

    test('should use the last path segment', () {
      expect(extensionOf(r'C:\Data\archive.tar.gz'), '.gz');
    });
  });
}

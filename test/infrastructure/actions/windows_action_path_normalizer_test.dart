import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';

void main() {
  group('WindowsActionPathNormalizer', () {
    test('should normalize extended-length and UNC paths for comparison', () {
      expect(
        WindowsActionPathNormalizer.normalizeForComparison(r'\\?\UNC\server\share\job.jar'),
        WindowsActionPathNormalizer.normalizeForComparison(r'\\server\share\job.jar'),
      );
      expect(
        WindowsActionPathNormalizer.normalizeForComparison(r'\\?\C:\Jobs\run.bat'),
        WindowsActionPathNormalizer.normalizeForComparison(r'C:\Jobs\run.bat'),
      );
    });

    test('should ignore trailing separators when comparing', () {
      expect(
        WindowsActionPathNormalizer.normalizeForComparison(r'C:\Jobs\'),
        WindowsActionPathNormalizer.normalizeForComparison('C:/Jobs'),
      );
    });

    test('should prefix extended path for local IO on Windows when path is long', () {
      if (!WindowsActionPathNormalizer.isWindows) {
        return;
      }

      final longPath = r'C:\${' + ('x' * 250) + r'}\file.txt';
      final ioPath = WindowsActionPathNormalizer.forLocalIo(longPath);
      expect(ioPath.startsWith(r'\\?\'), isTrue);
    });
  });
}

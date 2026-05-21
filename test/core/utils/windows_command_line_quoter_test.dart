import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/windows_command_line_quoter.dart';

void main() {
  group('WindowsCommandLineQuoter', () {
    test('should leave simple arguments unquoted', () {
      expect(WindowsCommandLineQuoter.quoteArgument('daily'), 'daily');
      expect(WindowsCommandLineQuoter.quoteArgument('--mode'), '--mode');
    });

    test('should quote arguments with spaces', () {
      expect(
        WindowsCommandLineQuoter.quoteArgument(r'C:\Program Files\job.exe'),
        r'"C:\Program Files\job.exe"',
      );
    });

    test('should escape embedded double quotes', () {
      expect(
        WindowsCommandLineQuoter.quoteArgument('Say"Hi'),
        r'"Say\"Hi"',
      );
    });

    test('should double trailing backslashes before a closing quote', () {
      expect(
        WindowsCommandLineQuoter.quoteArgument(r'C:\Temp\\'),
        r'"C:\Temp\\\\"',
      );
    });

    test('should join multiple quoted arguments with spaces', () {
      expect(
        WindowsCommandLineQuoter.joinArguments(<String>[
          r'C:\Program Files\Java\bin\java.exe',
          '-jar',
          r'C:\Program Files\Apps\job.jar',
        ]),
        r'"C:\Program Files\Java\bin\java.exe" -jar "C:\Program Files\Apps\job.jar"',
      );
    });
  });
}

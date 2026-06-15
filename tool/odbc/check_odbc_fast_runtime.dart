// Delegates to a Flutter test harness because plain `dart run` with odbc_fast FFI
// can fail with InvalidType/FFI in this workspace.
import 'dart:io';

Future<void> main(List<String> args) async {
  final requireColumnarCompressed = args.contains('--require-columnar-compressed');
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/odbc/check_odbc_fast_runtime.dart [--require-columnar-compressed]',
    );
    stdout.writeln(
      'Runs: flutter test test/tool/odbc_fast_runtime_check_test.dart',
    );
    return;
  }

  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final flutterArgs = <String>[
    'test',
    'test/tool/odbc_fast_runtime_check_test.dart',
  ];
  if (requireColumnarCompressed) {
    flutterArgs.add('--dart-define=REQUIRE_COLUMNAR_COMPRESSED=true');
  }

  final result = await Process.run(
    flutter,
    flutterArgs,
    runInShell: Platform.isWindows,
    workingDirectory: Directory.current.path,
  );

  final stdoutText = '${result.stdout}';
  final stderrText = '${result.stderr}';
  if (stdoutText.isNotEmpty) {
    stdout.write(stdoutText);
  }
  if (stderrText.isNotEmpty) {
    stderr.write(stderrText);
  }

  if (result.exitCode != 0 && requireColumnarCompressed) {
    stderr.writeln(
      'Required columnar/compressed runtime exports are not available.',
    );
  }

  exit(result.exitCode);
}

// Delegates to a Flutter test harness because plain `dart run` with odbc_fast FFI
// can fail with InvalidType/FFI in this workspace.
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: dart run tool/benchmarks/benchmark_odbc_pool_modes.dart');
    stdout.writeln('Runs: flutter test test/tool/odbc_pool_modes_benchmark_test.dart');
    return;
  }

  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final result = await Process.run(
    flutter,
    [
      'test',
      'test/tool/odbc_pool_modes_benchmark_test.dart',
    ],
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

  exit(result.exitCode);
}

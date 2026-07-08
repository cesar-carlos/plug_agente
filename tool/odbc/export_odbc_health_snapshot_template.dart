import 'dart:convert';
import 'dart:io';

import '../src/odbc_health_snapshot_template.dart';

Future<void> main(List<String> args) async {
  String? outputPath;
  var compact = false;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    switch (arg) {
      case '--output':
        if (index + 1 >= args.length) {
          stderr.writeln('Missing value for --output');
          exitCode = 64;
          return;
        }
        outputPath = args[++index];
      case '--compact':
        compact = true;
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run tool/odbc/export_odbc_health_snapshot_template.dart [--output path] [--compact]',
        );
        return;
      default:
        stderr.writeln('Unknown argument: $arg');
        exitCode = 64;
        return;
    }
  }

  final environment = readProcessEnvironmentWithDotEnv();
  final snapshot = await buildOdbcHealthSnapshotTemplate(
    environment: environment,
  );
  final encoder = compact ? const JsonEncoder() : const JsonEncoder.withIndent('  ');
  final payload = encoder.convert(snapshot);

  if (outputPath == null || outputPath.trim().isEmpty) {
    stdout.writeln(payload);
    return;
  }

  final file = File(outputPath);
  final parent = file.parent;
  if (!parent.existsSync()) {
    parent.createSync(recursive: true);
  }
  file.writeAsStringSync('$payload\n');
  stdout.writeln('Wrote health snapshot template to ${file.path}');
}

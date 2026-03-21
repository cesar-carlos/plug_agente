// ignore_for_file: avoid_print

/// Reads an LCOV `.info` file and writes a subset whose `SF:` paths match
/// prefixes (e.g. RPC + ODBC sources for multi-result coverage).
///
/// Usage:
/// `dart run tool/filter_lcov_info.dart coverage/lcov.info coverage/lcov_rpc.info lib/application/rpc/ lib/infrastructure/external_services/odbc_`
library;

import 'dart:io';

import 'lcov_path_filter.dart';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln(
      'Usage: dart run tool/filter_lcov_info.dart <input.info> <output.info> '
      '<path_prefix> [...]',
    );
    stderr.writeln(
      'Example: dart run tool/filter_lcov_info.dart coverage/lcov.info '
      'coverage/lcov_multi_result.info lib/application/rpc/ '
      'lib/infrastructure/external_services/odbc_',
    );
    exitCode = 64;
    return;
  }

  final input = File(args[0]);
  final output = File(args[1]);
  final prefixes = args.sublist(2);

  if (!input.existsSync()) {
    stderr.writeln('Input not found: ${input.path}');
    exitCode = 1;
    return;
  }

  final filtered = filterLcovByPathPrefixes(
    input.readAsStringSync(),
    prefixes,
  );
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(filtered);
  print('Wrote ${output.path} (${filtered.length} bytes)');
}

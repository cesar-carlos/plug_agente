// ignore_for_file: avoid_print

/// Prints LCOV files sorted by ascending line-hit ratio (lowest coverage first).
///
/// Usage: `dart run tool/summarize_lcov.dart [path/to/lcov.info]`
library;

import 'dart:io';

/// One record from an LCOV file (after `end_of_record`).
typedef LcovFileSummary = ({String path, int linesFound, int linesHit});

/// Parses [content] into per-file summaries using `SF:`, `LF:`, `LH:`.
List<LcovFileSummary> parseLcovSummaries(String content) {
  final out = <LcovFileSummary>[];
  String? sf;
  var lf = 0;
  var lh = 0;

  void flush() {
    if (sf == null) {
      return;
    }
    out.add((path: sf!, linesFound: lf, linesHit: lh));
    sf = null;
    lf = 0;
    lh = 0;
  }

  for (final raw in content.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.startsWith('SF:')) {
      flush();
      sf = line.substring(3).trim();
    } else if (line.startsWith('LF:')) {
      lf = int.tryParse(line.substring(3).trim()) ?? 0;
    } else if (line.startsWith('LH:')) {
      lh = int.tryParse(line.substring(3).trim()) ?? 0;
    } else if (line == 'end_of_record') {
      flush();
    }
  }
  flush();
  return out;
}

double hitRatio(LcovFileSummary r) {
  if (r.linesFound <= 0) {
    return 1;
  }
  return r.linesHit / r.linesFound;
}

void main(List<String> args) {
  final path = args.isEmpty ? 'coverage/lcov.info' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exitCode = 1;
    return;
  }
  final records = parseLcovSummaries(file.readAsStringSync());
  records.sort((a, b) => hitRatio(a).compareTo(hitRatio(b)));
  print('Lowest line coverage (LF/LH) — $path\n');
  for (final r in records) {
    if (r.linesFound <= 0) {
      continue;
    }
    final pct = (100 * hitRatio(r)).toStringAsFixed(1);
    print('${pct.padLeft(6)}%  ${r.linesHit}/${r.linesFound}  ${r.path}');
  }
}

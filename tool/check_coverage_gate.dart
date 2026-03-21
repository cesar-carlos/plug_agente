// ignore_for_file: avoid_print

/// Fails if aggregated line coverage for `lib/domain/` or `lib/application/`
/// under [coverage/lcov.info] is below configured minimums.
///
/// Default minimums match the current non-live test suite baseline (~71% domain,
/// ~75% application). Tighten over time via env (values 0–1 or 0–100):
/// - `COVERAGE_MIN_LIB_DOMAIN`
/// - `COVERAGE_MIN_LIB_APPLICATION`
///
/// Usage: `dart run tool/check_coverage_gate.dart [path/to/lcov.info]`
library;

import 'dart:io';

import 'summarize_lcov.dart' as lcov;

double _parseMinRatio(String? raw, double defaultFraction) {
  if (raw == null || raw.trim().isEmpty) {
    return defaultFraction;
  }
  final v = double.tryParse(raw.trim());
  if (v == null) {
    return defaultFraction;
  }
  return v > 1 ? v / 100 : v;
}

({int found, int hit}) _aggregateForPrefix(
  List<lcov.LcovFileSummary> records,
  String pathSubstring,
) {
  var found = 0;
  var hit = 0;
  for (final r in records) {
    final p = r.path.replaceAll(r'\', '/');
    // LCOV SF paths are repo-relative, e.g. `lib/domain/foo.dart`.
    if (!p.contains(pathSubstring)) {
      continue;
    }
    found += r.linesFound;
    hit += r.linesHit;
  }
  return (found: found, hit: hit);
}

void main(List<String> args) {
  final path = args.isEmpty ? 'coverage/lcov.info' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: $path');
    stderr.writeln('Run: flutter test --coverage --exclude-tags=live');
    exitCode = 1;
    return;
  }

  final minDomain = _parseMinRatio(
    Platform.environment['COVERAGE_MIN_LIB_DOMAIN'],
    0.71,
  );
  final minApplication = _parseMinRatio(
    Platform.environment['COVERAGE_MIN_LIB_APPLICATION'],
    0.74,
  );

  final records = lcov.parseLcovSummaries(file.readAsStringSync());
  final domain = _aggregateForPrefix(records, 'lib/domain/');
  final application = _aggregateForPrefix(records, 'lib/application/');

  double ratio(int found, int hit) =>
      found <= 0 ? 1.0 : hit / found;

  final domainRatio = ratio(domain.found, domain.hit);
  final appRatio = ratio(application.found, application.hit);

  var ok = true;
  if (domainRatio < minDomain) {
    ok = false;
    stderr.writeln(
      'Coverage gate failed: lib/domain/ ${(100 * domainRatio).toStringAsFixed(1)}% '
      '(${domain.hit}/${domain.found} lines) < ${(100 * minDomain).toStringAsFixed(1)}%',
    );
  }
  if (appRatio < minApplication) {
    ok = false;
    stderr.writeln(
      'Coverage gate failed: lib/application/ ${(100 * appRatio).toStringAsFixed(1)}% '
      '(${application.hit}/${application.found} lines) < ${(100 * minApplication).toStringAsFixed(1)}%',
    );
  }

  if (!ok) {
    stderr.writeln(
      'Adjust tests or set COVERAGE_MIN_LIB_DOMAIN / COVERAGE_MIN_LIB_APPLICATION.',
    );
    exitCode = 1;
    return;
  }

  print(
    'Coverage gate OK: lib/domain/ ${(100 * domainRatio).toStringAsFixed(1)}% '
    '(${domain.hit}/${domain.found}), '
    'lib/application/ ${(100 * appRatio).toStringAsFixed(1)}% '
    '(${application.hit}/${application.found})',
  );
}

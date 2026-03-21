import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Resolves the project root (directory containing `pubspec.yaml`) by walking up.
Directory? resolveE2eProjectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 16; i++) {
    final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}

/// Best-effort VCS revision for trend charts (never throws).
String? resolveE2eGitRevision() {
  final fromEnv =
      Platform.environment['GITHUB_SHA']?.trim() ??
      Platform.environment['GIT_COMMIT']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv;
  }
  final root = resolveE2eProjectRoot();
  if (root == null) {
    return null;
  }
  try {
    final r = Process.runSync(
      'git',
      <String>['rev-parse', 'HEAD'],
      workingDirectory: root.path,
      runInShell: true,
    );
    if (r.exitCode == 0) {
      final out = (r.stdout as String).trim();
      if (out.isNotEmpty) {
        return out;
      }
    }
  } on Object {
    // ignore
  }
  return null;
}

/// Summary of repeated async timings (milliseconds per sample).
class E2eBenchmarkStats {
  const E2eBenchmarkStats({
    required this.warmup,
    required this.iterations,
    required this.samplesMs,
  });

  final int warmup;
  final int iterations;
  final List<int> samplesMs;

  double get meanMs {
    if (samplesMs.isEmpty) {
      return 0;
    }
    final sum = samplesMs.fold<int>(0, (a, b) => a + b);
    return sum / samplesMs.length;
  }

  int get minMs => samplesMs.isEmpty ? 0 : samplesMs.reduce(math.min);

  int get maxMs => samplesMs.isEmpty ? 0 : samplesMs.reduce(math.max);

  int get medianMs {
    if (samplesMs.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(samplesMs)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  /// Nearest-rank ~90th percentile on sorted samples (coarse for small N).
  int get p90Ms {
    if (samplesMs.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(samplesMs)..sort();
    final n = sorted.length;
    final idx = (n * 0.9).ceil() - 1;
    return sorted[idx.clamp(0, n - 1)];
  }

  /// Nearest-rank ~95th percentile on sorted samples (coarse for small N).
  int get p95Ms {
    if (samplesMs.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(samplesMs)..sort();
    final n = sorted.length;
    final idx = (n * 0.95).ceil() - 1;
    return sorted[idx.clamp(0, n - 1)];
  }

  /// Mean after dropping one min and one max (falls back to [meanMs] if N < 3).
  double get trimmedMeanMs {
    if (samplesMs.isEmpty) {
      return 0;
    }
    if (samplesMs.length < 3) {
      return meanMs;
    }
    final sorted = List<int>.from(samplesMs)..sort();
    final slice = sorted.sublist(1, sorted.length - 1);
    final sum = slice.fold<int>(0, (int a, int b) => a + b);
    return sum / slice.length;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'warmup': warmup,
    'iterations': iterations,
    'mean_ms': meanMs,
    'min_ms': minMs,
    'max_ms': maxMs,
    'median_ms': medianMs,
    'p90_ms': p90Ms,
    'p95_ms': p95Ms,
    'trimmed_mean_ms': trimmedMeanMs,
    'samples_ms': List<int>.from(samplesMs),
  };

  /// Runs [body] [warmup] times, then collects [iterations] samples (wall clock).
  static Future<E2eBenchmarkStats> measureAsync(
    Future<void> Function() body, {
    int warmup = 2,
    int iterations = 8,
  }) async {
    for (var i = 0; i < warmup; i++) {
      await body();
    }
    final samples = <int>[];
    final sw = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      sw
        ..reset()
        ..start();
      await body();
      sw.stop();
      samples.add(sw.elapsedMilliseconds);
    }
    return E2eBenchmarkStats(
      warmup: warmup,
      iterations: iterations,
      samplesMs: samples,
    );
  }

  /// Single sample in milliseconds (for one-off operations).
  static E2eBenchmarkStats single(int elapsedMs) => E2eBenchmarkStats(
    warmup: 0,
    iterations: 1,
    samplesMs: <int>[elapsedMs],
  );
}

/// Appends one JSON object per line (JSONL) for local history / tooling.
void appendE2eBenchmarkRecord({
  required File file,
  required Map<String, dynamic> record,
}) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${jsonEncode(record)}\n',
    mode: FileMode.append,
    flush: true,
  );
}

/// [configuredPath] from env: absolute path as-is, else joined to [resolveE2eProjectRoot].
File resolveE2eBenchmarkOutputFile(String configuredPath) {
  if (p.isAbsolute(configuredPath)) {
    return File(configuredPath);
  }
  final root = resolveE2eProjectRoot()?.path ?? Directory.current.path;
  return File(p.normalize(p.join(root, configuredPath)));
}

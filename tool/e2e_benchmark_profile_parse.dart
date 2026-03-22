class OdbcE2eBenchmarkProfile {
  const OdbcE2eBenchmarkProfile({
    required this.poolMode,
    required this.poolSize,
    required this.concurrency,
  });

  final String poolMode;
  final int poolSize;
  final int concurrency;

  String get key => '${poolMode}_p${poolSize}_c$concurrency';

  String get label => '$poolMode p$poolSize c$concurrency';
}

enum OdbcE2eBenchmarkProfileSource {
  single,
  customMatrix,
  defaultMatrix,
}

class ResolvedOdbcE2eBenchmarkProfiles {
  const ResolvedOdbcE2eBenchmarkProfiles({
    required this.source,
    required this.profiles,
  });

  final OdbcE2eBenchmarkProfileSource source;
  final List<OdbcE2eBenchmarkProfile> profiles;
}

const List<OdbcE2eBenchmarkProfile> kDefaultOdbcE2eBenchmarkProfiles =
    <OdbcE2eBenchmarkProfile>[
      OdbcE2eBenchmarkProfile(
        poolMode: 'lease',
        poolSize: 2,
        concurrency: 4,
      ),
      OdbcE2eBenchmarkProfile(
        poolMode: 'lease',
        poolSize: 4,
        concurrency: 8,
      ),
    ];

/// Native ODBC uses `odbc_fast`'s single async worker (~30s request timeout per
/// call). When benchmark concurrency exceeds pool size, queued worker requests
/// can exceed that timeout even though the pool is not logically exhausted.
List<OdbcE2eBenchmarkProfile> normalizeOdbcE2eBenchmarkProfilesForNativeWorker(
  List<OdbcE2eBenchmarkProfile> profiles,
) {
  return profiles
      .map((OdbcE2eBenchmarkProfile p) {
        if (p.poolMode != 'native') {
          return p;
        }
        if (p.poolSize >= p.concurrency) {
          return p;
        }
        return OdbcE2eBenchmarkProfile(
          poolMode: p.poolMode,
          poolSize: p.concurrency,
          concurrency: p.concurrency,
        );
      })
      .toList(growable: false);
}

ResolvedOdbcE2eBenchmarkProfiles resolveOdbcE2eBenchmarkProfiles({
  required String? matrixRaw,
  required String? poolModeRaw,
  required String? poolSizeRaw,
  required String? concurrencyRaw,
  required int defaultPoolSize,
  required int defaultConcurrency,
}) {
  final parsedMatrix = _parseProfileMatrix(
    matrixRaw,
    defaultPoolSize: defaultPoolSize,
    defaultConcurrency: defaultConcurrency,
  );
  if (parsedMatrix.isNotEmpty) {
    return ResolvedOdbcE2eBenchmarkProfiles(
      source: OdbcE2eBenchmarkProfileSource.customMatrix,
      profiles: normalizeOdbcE2eBenchmarkProfilesForNativeWorker(parsedMatrix),
    );
  }

  final hasExplicitSingle =
      _hasEnvValue(poolModeRaw) ||
      _hasEnvValue(poolSizeRaw) ||
      _hasEnvValue(concurrencyRaw);
  if (hasExplicitSingle) {
    return ResolvedOdbcE2eBenchmarkProfiles(
      source: OdbcE2eBenchmarkProfileSource.single,
      profiles: normalizeOdbcE2eBenchmarkProfilesForNativeWorker(
        <OdbcE2eBenchmarkProfile>[
          OdbcE2eBenchmarkProfile(
            poolMode: _normalizePoolMode(poolModeRaw),
            poolSize: _parsePositiveInt(poolSizeRaw) ?? defaultPoolSize,
            concurrency: _parsePositiveInt(concurrencyRaw) ?? defaultConcurrency,
          ),
        ],
      ),
    );
  }

  return ResolvedOdbcE2eBenchmarkProfiles(
    source: OdbcE2eBenchmarkProfileSource.defaultMatrix,
    profiles: normalizeOdbcE2eBenchmarkProfilesForNativeWorker(
      List<OdbcE2eBenchmarkProfile>.from(kDefaultOdbcE2eBenchmarkProfiles),
    ),
  );
}

List<OdbcE2eBenchmarkProfile> _parseProfileMatrix(
  String? raw, {
  required int defaultPoolSize,
  required int defaultConcurrency,
}) {
  if (!_hasEnvValue(raw)) {
    return const <OdbcE2eBenchmarkProfile>[];
  }

  final entries = raw!
      .split(RegExp(r'[;\r\n]+'))
      .map((String entry) => entry.trim())
      .where((String entry) => entry.isNotEmpty);

  final out = <OdbcE2eBenchmarkProfile>[];
  for (final entry in entries) {
    final profile = _parseProfileEntry(
      entry,
      defaultPoolSize: defaultPoolSize,
      defaultConcurrency: defaultConcurrency,
    );
    if (profile != null) {
      out.add(profile);
    }
  }

  return out;
}

OdbcE2eBenchmarkProfile? _parseProfileEntry(
  String raw, {
  required int defaultPoolSize,
  required int defaultConcurrency,
}) {
  final parts = raw
      .split(':')
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return null;
  }

  final poolMode = _normalizePoolMode(parts.first);
  var poolSize = defaultPoolSize;
  var concurrency = defaultConcurrency;
  var sawNumericPool = false;

  for (final part in parts.skip(1)) {
    final lower = part.toLowerCase();
    final value = _parsePositiveInt(part);
    if (value == null) {
      continue;
    }

    if (lower.startsWith('c')) {
      concurrency = value;
      continue;
    }
    if (lower.startsWith('p') || lower.startsWith('pool')) {
      poolSize = value;
      sawNumericPool = true;
      continue;
    }
    if (!sawNumericPool) {
      poolSize = value;
      sawNumericPool = true;
      continue;
    }
    concurrency = value;
  }

  return OdbcE2eBenchmarkProfile(
    poolMode: poolMode,
    poolSize: poolSize,
    concurrency: concurrency,
  );
}

String _normalizePoolMode(String? raw) {
  if (raw?.trim().toLowerCase() == 'native') {
    return 'native';
  }
  return 'lease';
}

int? _parsePositiveInt(String? raw) {
  final value = int.tryParse(
    RegExp(r'(\d+)').firstMatch(raw ?? '')?.group(1) ?? '',
  );
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}

bool _hasEnvValue(String? raw) => raw != null && raw.trim().isNotEmpty;

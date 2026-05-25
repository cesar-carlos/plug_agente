class AppVersionComparator {
  const AppVersionComparator._();

  static int compare(String left, String right) {
    final leftVersion = _ParsedAppVersion.parse(left);
    final rightVersion = _ParsedAppVersion.parse(right);
    return leftVersion.compareTo(rightVersion);
  }

  static bool isRemoteVersionNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    return compare(remoteVersion, currentVersion) > 0;
  }
}

class _ParsedAppVersion implements Comparable<_ParsedAppVersion> {
  const _ParsedAppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static _ParsedAppVersion parse(String value) {
    final normalized = value.trim();
    // Strip optional SemVer pre-release label, preserving any build metadata:
    //   "1.2.3-beta.1"    → "1.2.3"
    //   "1.2.3-rc.1+5"    → "1.2.3+5"
    //   "1.2.3+5"         → "1.2.3+5"  (unchanged)
    final String withoutPreRelease;
    final dashIndex = normalized.indexOf('-');
    if (dashIndex >= 0) {
      final plusIndex = normalized.indexOf('+');
      withoutPreRelease = plusIndex > dashIndex
          ? normalized.substring(0, dashIndex) + normalized.substring(plusIndex)
          : normalized.substring(0, dashIndex);
    } else {
      withoutPreRelease = normalized;
    }
    final parts = withoutPreRelease.split('+');
    final semanticParts = parts.first.split('.');
    if (semanticParts.length != 3 || parts.length > 2) {
      throw FormatException('Invalid app version: $value');
    }

    return _ParsedAppVersion(
      major: _parseNonNegative(semanticParts[0], value),
      minor: _parseNonNegative(semanticParts[1], value),
      patch: _parseNonNegative(semanticParts[2], value),
      build: parts.length == 2 ? _parseNonNegative(parts[1], value) : 0,
    );
  }

  static int _parseNonNegative(String raw, String source) {
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw FormatException('Invalid app version: $source');
    }
    return value;
  }

  @override
  int compareTo(_ParsedAppVersion other) {
    final fields = <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ];
    for (final field in fields) {
      final diff = field.$1.compareTo(field.$2);
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }
}

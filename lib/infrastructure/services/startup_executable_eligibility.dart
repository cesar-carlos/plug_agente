/// Path helpers that decide whether an executable may be persisted as the
/// Windows Run key target.
///
/// Detection is path-based (not `kDebugMode`) so unit tests can pass mocked
/// Program Files paths while `flutter run` / build-tree processes are refused.
String normalizeStartupExecutablePath(String executablePath) {
  return executablePath.trim().replaceAll('/', r'\').toLowerCase();
}

/// Returns true when [executablePath] is a Flutter debug/profile/build-tree
/// output that must not be persisted as the Windows Run key target.
bool isNonProductionStartupExecutable(String executablePath) {
  final normalized = normalizeStartupExecutablePath(executablePath);
  if (normalized.isEmpty) {
    return false;
  }

  return normalized.contains(r'\build\windows\') ||
      normalized.contains(r'\.dart_tool\') ||
      normalized.contains(r'\flutter\ephemeral\');
}

/// Installed-looking locations that are safe to persist as the Run key.
bool isStableInstalledStartupExecutable(String executablePath) {
  if (isNonProductionStartupExecutable(executablePath)) {
    return false;
  }

  final normalized = normalizeStartupExecutablePath(executablePath);
  if (normalized.isEmpty) {
    return false;
  }

  return normalized.contains(r'\program files\') ||
      normalized.contains(r'\program files (x86)\') ||
      normalized.contains(r'\appdata\local\programs\');
}

bool isSameStartupExecutableDirectory(String left, String right) {
  final leftDirectory = _executableDirectory(left);
  final rightDirectory = _executableDirectory(right);
  return leftDirectory.isNotEmpty && leftDirectory == rightDirectory;
}

/// Whether the current process path may be written to the Run key.
///
/// Build-tree paths are always refused. A non-installed copy is refused when
/// a healthy production Run key already points at a different stable install.
bool canPersistStartupExecutable(
  String executablePath, {
  String? existingHealthyExecutablePath,
}) {
  if (isNonProductionStartupExecutable(executablePath)) {
    return false;
  }
  if (isStableInstalledStartupExecutable(executablePath)) {
    return true;
  }

  final existing = existingHealthyExecutablePath?.trim();
  if (existing == null || existing.isEmpty) {
    return true;
  }
  if (isNonProductionStartupExecutable(existing)) {
    return true;
  }
  if (isSameStartupExecutableDirectory(executablePath, existing)) {
    return true;
  }
  if (isStableInstalledStartupExecutable(existing)) {
    return false;
  }
  return true;
}

String _executableDirectory(String executablePath) {
  final normalized = normalizeStartupExecutablePath(executablePath);
  final separator = normalized.lastIndexOf(r'\');
  if (separator <= 0) {
    return '';
  }
  return normalized.substring(0, separator);
}

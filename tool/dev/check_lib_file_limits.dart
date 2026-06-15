import 'dart:io';

const int defaultMaxLines = 600;
const int defaultMaxImports = 40;

final RegExp _generatedSuffix = RegExp(r'\.g\.dart$');
final RegExp _importPattern = RegExp("^import '");

bool _isExcluded(String relativePath) {
  if (_generatedSuffix.hasMatch(relativePath)) {
    return true;
  }
  if (relativePath.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}')) {
    return true;
  }
  return false;
}

void main(List<String> args) {
  final maxLines = _readIntArg(args, '--max-lines', defaultMaxLines);
  final maxImports = _readIntArg(args, '--max-imports', defaultMaxImports);
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('lib/ directory not found');
    exit(2);
  }

  final violations = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relative = entity.path.replaceAll(r'\', '/');
    final fromLib = relative.startsWith('lib/') ? relative.substring(4) : relative;
    if (_isExcluded(fromLib)) {
      continue;
    }

    final lines = entity.readAsLinesSync();
    if (lines.length > maxLines) {
      violations.add('$fromLib: ${lines.length} lines (max $maxLines)');
    }

    final importCount = lines.where((line) => _importPattern.hasMatch(line.trim())).length;
    if (importCount > maxImports) {
      violations.add('$fromLib: $importCount imports (max $maxImports)');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('All lib/ files within limits (lines<=$maxLines, imports<=$maxImports).');
    exit(0);
  }

  stderr.writeln('File limit violations (${violations.length}):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exit(1);
}

int _readIntArg(List<String> args, String name, int fallback) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return fallback;
  }
  return int.tryParse(args[index + 1]) ?? fallback;
}

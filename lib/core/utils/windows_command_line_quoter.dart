/// Builds Windows command-line argument strings per MSVC parsing rules.
///
/// Used for support previews and diagnostics; structured Process.start argv does
/// not require this quoting at runtime.
abstract final class WindowsCommandLineQuoter {
  static String quoteArgument(String argument) {
    if (argument.isEmpty) {
      return '""';
    }

    if (!_needsQuoting(argument)) {
      return argument;
    }

    final buffer = StringBuffer('"');
    for (var index = 0; index < argument.length; index++) {
      final codeUnit = argument.codeUnitAt(index);
      if (codeUnit != 0x5C) {
        if (codeUnit == 0x22) {
          buffer.write(r'\"');
        } else {
          buffer.writeCharCode(codeUnit);
        }
        continue;
      }

      var backslashCount = 1;
      while (index + backslashCount < argument.length && argument.codeUnitAt(index + backslashCount) == 0x5C) {
        backslashCount++;
      }

      final nextIndex = index + backslashCount;
      if (nextIndex >= argument.length) {
        buffer.write(r'\' * (backslashCount * 2));
        break;
      }

      if (argument.codeUnitAt(nextIndex) == 0x22) {
        buffer.write(r'\' * (backslashCount * 2 + 1));
        buffer.write('"');
        index = nextIndex;
        continue;
      }

      buffer.write(r'\' * backslashCount);
      index = nextIndex - 1;
    }

    buffer.write('"');
    return buffer.toString();
  }

  static String joinArguments(Iterable<String> arguments) {
    return arguments.map(quoteArgument).join(' ');
  }

  static bool _needsQuoting(String argument) {
    if (argument.endsWith(r'\')) {
      return true;
    }

    for (var index = 0; index < argument.length; index++) {
      final codeUnit = argument.codeUnitAt(index);
      if (codeUnit <= 0x20 || codeUnit == 0x22) {
        return true;
      }
    }

    return false;
  }
}

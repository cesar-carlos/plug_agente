class TraceContextValidator {
  const TraceContextValidator._();

  static final RegExp _traceParentPattern = RegExp(
    r'^[\da-f]{2}-[\da-f]{32}-[\da-f]{16}-[\da-f]{2}$',
    caseSensitive: false,
  );
  static final RegExp _tracestateKeyPattern = RegExp(
    r'^[a-z0-9][_a-z0-9\-\*\/]{0,240}(?:@[a-z0-9][_a-z0-9\-\*\/]{0,13})?$',
  );

  static bool isValidTraceParent(String value) {
    return _traceParentPattern.hasMatch(value);
  }

  static bool isValidTraceState(String value) {
    if (value.isEmpty || value.length > 512) {
      return false;
    }

    final members = value.split(',');
    if (members.length > 32) {
      return false;
    }

    for (final member in members) {
      final trimmed = member.trim();
      final separatorIndex = trimmed.indexOf('=');
      if (separatorIndex <= 0 || separatorIndex == trimmed.length - 1) {
        return false;
      }

      final key = trimmed.substring(0, separatorIndex);
      final entryValue = trimmed.substring(separatorIndex + 1);
      if (!_tracestateKeyPattern.hasMatch(key) || !_isValidTraceStateValue(entryValue)) {
        return false;
      }
    }

    return true;
  }

  static bool _isValidTraceStateValue(String value) {
    if (value.isEmpty || value.length > 256) {
      return false;
    }

    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit > 0x7E || codeUnit == 0x2C) {
        return false;
      }
    }
    return true;
  }
}

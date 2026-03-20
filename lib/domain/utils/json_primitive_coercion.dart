// Coercion for JSON-decoded values where num may be int or double.

int? jsonWholeNumberAsInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is double) {
    if (value.isNaN || value.isInfinite) {
      return null;
    }
    if (value != value.roundToDouble()) {
      return null;
    }
    return value.toInt();
  }
  return null;
}

/// Whole number >= 1, or null if missing / invalid.
int? jsonPositiveInt(Object? value) {
  final n = jsonWholeNumberAsInt(value);
  if (n == null || n < 1) {
    return null;
  }
  return n;
}

int jsonPositiveIntWithDefault(Object? value, int defaultValue) =>
    jsonPositiveInt(value) ?? defaultValue;

/// Whole number >= 0, or null if missing / invalid.
int? jsonNonNegativeInt(Object? value) {
  final n = jsonWholeNumberAsInt(value);
  if (n == null || n < 0) {
    return null;
  }
  return n;
}

int jsonNonNegativeIntWithDefault(Object? value, int defaultValue) =>
    jsonNonNegativeInt(value) ?? defaultValue;

DateTime? parseJwtNumericDate(Object? value, {required String claim}) {
  if (value == null) return null;
  const maxDateTimeSeconds = 8640000000000;
  if (value is! num || !value.isFinite || value < -maxDateTimeSeconds || value > maxDateTimeSeconds) {
    throw FormatException('Invalid JWT timestamp: $claim');
  }
  final seconds = value.truncate();
  final fractionalMicroseconds = ((value - seconds) * Duration.microsecondsPerSecond).floor();
  return DateTime.fromMicrosecondsSinceEpoch(
    seconds * Duration.microsecondsPerSecond + fractionalMicroseconds,
    isUtc: true,
  );
}

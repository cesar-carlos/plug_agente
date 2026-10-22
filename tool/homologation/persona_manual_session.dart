/// Fixture lifetime only; does not alter SQL, approval or authentication limits.
DateTime fixtureSessionDeadline(
  Map<String, Object?> manifest,
  Duration standardLifetime, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (!manifest.containsKey('manualTraining')) return current.add(standardLifetime);
  final manual = manifest['manualTraining'];
  if (manual is! Map<String, Object?> ||
      manual.length != 2 ||
      manual['format'] != 'persona-manual-training-v1' ||
      manual['expiresAt'] is! String) {
    throw StateError('Invalid bounded manual fixture lifetime.');
  }
  final text = manual['expiresAt']! as String;
  final deadline = DateTime.tryParse(text);
  if (!text.endsWith('Z') ||
      deadline == null ||
      !deadline.isAfter(current) ||
      deadline.isAfter(current.add(const Duration(hours: 2)))) {
    throw StateError('Expired or excessive manual fixture lifetime.');
  }
  return deadline;
}

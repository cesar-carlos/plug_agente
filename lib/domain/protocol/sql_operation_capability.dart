/// Versioned transport support, distinct from policy and driver authorization.
abstract final class SqlOperationCapability {
  static const key = 'sqlOperations';
  static const version = 1;
  static const limits = {'maxSteps': 32, 'maxAffectedRows': 100000, 'timeoutMs': 300000};
  static const advertisement = <String, dynamic>{
    'enabled': true,
    'version': version,
    'durableJournal': true,
    'singleSourceTransaction': true,
    'automaticReplay': false,
    ...limits,
  };

  static Map<String, dynamic>? negotiate(Object? local, Object? remote) {
    if (!supported(local) || !supported(remote)) return null;
    final a = local! as Map;
    final b = remote! as Map;
    return {
      ...advertisement,
      for (final entry in limits.entries)
        entry.key: [a[entry.key] as int, b[entry.key] as int, entry.value].reduce((x, y) => x < y ? x : y),
    };
  }

  static bool supported(Object? raw) =>
      raw is Map &&
      raw['enabled'] == true &&
      raw['version'] == version &&
      raw['version'] is int &&
      raw['durableJournal'] == true &&
      raw['singleSourceTransaction'] == true &&
      raw['automaticReplay'] == false &&
      limits.keys.every((key) => raw[key] is int && (raw[key] as int) > 0);
}

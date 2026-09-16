import 'dart:collection';

import 'package:plug_agente/core/constants/connection_constants.dart';

/// Small, content-agnostic LRU used by automatic outbound compression.
///
/// A negative result is keyed only by event name and a coarse byte-size tier.
/// It never observes payload content, so it neither retains application data
/// nor makes compression decisions based on secrets.
class AdaptiveCompressionCache {
  AdaptiveCompressionCache({
    this.maxEntries = ConnectionConstants.adaptiveCompressionCacheMaxEntries,
    this.ttl = ConnectionConstants.adaptiveCompressionSkipTtl,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _now;
  final LinkedHashMap<String, DateTime> _incompressibleUntil = LinkedHashMap<String, DateTime>();

  int skippedAttempts = 0;
  int avoidedInputBytes = 0;
  int ineffectiveAttempts = 0;
  int effectiveAttempts = 0;

  bool shouldSkip({required String? eventName, required int originalSize}) {
    final key = _key(eventName, originalSize);
    final until = _incompressibleUntil.remove(key);
    if (until == null || !until.isAfter(_now())) {
      return false;
    }
    _incompressibleUntil[key] = until;
    skippedAttempts++;
    avoidedInputBytes += originalSize;
    return true;
  }

  void recordAttempt({
    required String? eventName,
    required int originalSize,
    required bool reduced,
  }) {
    if (reduced) {
      effectiveAttempts++;
      _incompressibleUntil.remove(_key(eventName, originalSize));
      return;
    }
    ineffectiveAttempts++;
    final key = _key(eventName, originalSize);
    _incompressibleUntil.remove(key);
    _incompressibleUntil[key] = _now().add(ttl);
    while (_incompressibleUntil.length > maxEntries.clamp(1, 1024)) {
      _incompressibleUntil.remove(_incompressibleUntil.keys.first);
    }
  }

  void clear() => _incompressibleUntil.clear();

  static String _key(String? eventName, int originalSize) {
    final event = (eventName == null || eventName.isEmpty) ? 'unknown' : eventName;
    // log2 tiers avoid coupling a 64-byte variance to a separate cache entry.
    var tier = 0;
    var value = originalSize < 1 ? 1 : originalSize;
    while (value > 1) {
      value >>= 1;
      tier++;
    }
    return '$event:$tier';
  }
}

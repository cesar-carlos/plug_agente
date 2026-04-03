/// Threshold (estimated UTF-8 JSON size) to offload encoding / hashing work to an
/// isolate. Kept in sync with inbound JSON decode isolate threshold (384 KiB).
const int jsonPayloadIsolateEncodeThresholdBytes = 384 * 1024;

/// Conservative estimate of serialized JSON UTF-8 size without building the
/// full string. Used to choose isolate vs synchronous JSON work.
bool jsonTreeLikelyExceedsByteBudget(dynamic value, int budgetBytes) {
  if (budgetBytes <= 0) {
    return false;
  }
  var used = 0;

  bool walk(dynamic v, int depth) {
    if (depth > 64) {
      return true;
    }
    if (used > budgetBytes) {
      return true;
    }
    if (v == null) {
      used += 4;
      return false;
    }
    if (v is bool) {
      used += 5;
      return false;
    }
    if (v is num) {
      used += 24;
      return false;
    }
    if (v is String) {
      used += 2 + v.length * 3;
      return used > budgetBytes;
    }
    if (v is Map) {
      used += 2;
      for (final entry in v.entries) {
        final key = entry.key;
        if (key is String) {
          used += 4 + key.length * 3;
        } else {
          used += 12;
        }
        if (walk(entry.value, depth + 1)) {
          return true;
        }
      }
      return used > budgetBytes;
    }
    if (v is List) {
      used += 2;
      for (final dynamic e in v) {
        if (walk(e, depth + 1)) {
          return true;
        }
      }
      return used > budgetBytes;
    }
    used += 16;
    return used > budgetBytes;
  }

  return walk(value, 0);
}

import 'dart:collection';

import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';

/// Classifies materialized SQL queue submissions into worker lanes.
///
/// Caches recent classifications so repeated hub/playground queries avoid
/// re-running regex and length checks on every enqueue.
class SqlExecutionKindClassifier {
  SqlExecutionKindClassifier({int cacheCapacity = 128}) : _cacheCapacity = cacheCapacity;

  static final RegExp longQueryPattern = RegExp(
    r'\b(join|union|group\s+by|order\s+by)\b',
    caseSensitive: false,
  );

  final int _cacheCapacity;
  final LinkedHashMap<String, SqlExecutionKind> _cache = LinkedHashMap();

  SqlExecutionKind classify(QueryRequest request, Duration? timeout) {
    final key = _cacheKey(request, timeout);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final kind = _classifyUncached(request, timeout);
    _cache[key] = kind;
    if (_cache.length > _cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return kind;
  }

  String _cacheKey(QueryRequest request, Duration? timeout) {
    final normalizedSql = request.query.trim();
    return '${request.expectMultipleResults}0${timeout?.inMilliseconds ?? 0}0$normalizedSql';
  }

  SqlExecutionKind _classifyUncached(
    QueryRequest request,
    Duration? timeout,
  ) {
    final normalizedSql = request.query.trim();
    final timeoutMs = timeout?.inMilliseconds ?? 0;
    if (request.expectMultipleResults ||
        normalizedSql.length > 1200 ||
        timeoutMs > 15000 ||
        longQueryPattern.hasMatch(normalizedSql)) {
      return SqlExecutionKind.longQuery;
    }
    return SqlExecutionKind.shortQuery;
  }
}

import 'dart:convert';

/// Truncates payloads above a UTF-8 byte budget when shipping them to the
/// message tracer; below the budget the original object is returned untouched
/// so logs preserve diagnostic detail.
///
/// Includes a cheap structural short-circuit that skips the JSON encode/budget
/// probe for obvious "small" payloads (most heartbeats, acks, simple RPC
/// requests/responses) — saves an allocation per logged event.
class PayloadLogSummarizer {
  PayloadLogSummarizer({
    required this.thresholdBytes,
    int? shortCircuitMaxMapEntries,
    int? shortCircuitMaxStringChars,
  }) : shortCircuitMaxMapEntries = shortCircuitMaxMapEntries ?? 32,
       shortCircuitMaxStringChars = shortCircuitMaxStringChars ?? 256;

  final int thresholdBytes;
  final int shortCircuitMaxMapEntries;
  final int shortCircuitMaxStringChars;

  /// Returns [data] when the encoded JSON fits under [thresholdBytes], or a
  /// summary map describing the payload otherwise. Returns [data] unchanged on
  /// any unexpected encoding error.
  dynamic summarize(String direction, String event, dynamic data) {
    if (_isObviouslySmall(data)) {
      return data;
    }
    try {
      final sink = _Utf8BudgetSink(thresholdBytes);
      final jsonSink = JsonUtf8Encoder().startChunkedConversion(sink);
      jsonSink.add(data);
      jsonSink.close();
      return data;
    } on _PayloadUtf8BudgetExceeded {
      return <String, Object?>{
        '_log': 'payload_summary',
        'direction': direction,
        'event': event,
        'truncated': true,
        'threshold_bytes': thresholdBytes,
        if (data is Map<String, dynamic>) ..._shallowRpcLogHints(data),
        if (data is List<dynamic>) 'list_length': data.length,
      };
    } on Object {
      return data;
    }
  }

  /// Returns `true` when the JSON-encoded representation of [payload] would
  /// exceed [budgetBytes]. Used by the transport to decide if a payload is
  /// over the negotiated logical limit before attempting to send it.
  bool exceedsByteBudget(dynamic payload, int budgetBytes) {
    if (budgetBytes <= 0) {
      return false;
    }
    try {
      final sink = _Utf8BudgetSink(budgetBytes);
      final jsonSink = JsonUtf8Encoder().startChunkedConversion(sink);
      jsonSink.add(payload);
      jsonSink.close();
      return false;
    } on _PayloadUtf8BudgetExceeded {
      return true;
    }
  }

  Map<String, Object?> _shallowRpcLogHints(Map<String, dynamic> map) {
    return <String, Object?>{
      if (map.containsKey('id')) 'id': map['id'],
      if (map.containsKey('method')) 'method': map['method'],
      if (map.containsKey('jsonrpc')) 'jsonrpc': map['jsonrpc'],
    };
  }

  bool _isObviouslySmall(dynamic data) {
    if (data == null || data is num || data is bool) return true;
    if (data is String) {
      return data.length < shortCircuitMaxStringChars;
    }
    if (data is Map<String, dynamic>) {
      if (data.length >= shortCircuitMaxMapEntries) return false;
      for (final value in data.values) {
        if (value is String) {
          if (value.length >= shortCircuitMaxStringChars) return false;
          continue;
        }
        if (value is num || value is bool || value == null) continue;
        return false;
      }
      return true;
    }
    return false;
  }
}

class _PayloadUtf8BudgetExceeded implements Exception {
  const _PayloadUtf8BudgetExceeded();
}

class _Utf8BudgetSink extends ByteConversionSinkBase {
  _Utf8BudgetSink(this.budgetBytes);

  final int budgetBytes;
  int _total = 0;

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    if (_total > budgetBytes) {
      throw const _PayloadUtf8BudgetExceeded();
    }
  }

  @override
  void close() {}
}

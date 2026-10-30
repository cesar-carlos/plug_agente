import 'package:plug_agente/domain/protocol/protocol.dart';

/// Helpers for JSON-RPC wire maps where optional schema fields must be omitted,
/// not sent as JSON `null` (JSON Schema treats present `null` as a type error).
abstract final class RpcWireMap {
  RpcWireMap._();

  static void putOptionalInt(
    Map<String, dynamic> target,
    String key,
    int? value,
  ) {
    if (value != null) {
      target[key] = value;
    }
  }

  static void putOptionalBool(
    Map<String, dynamic> target,
    String key,
    bool? value,
  ) {
    if (value != null) {
      target[key] = value;
    }
  }

  /// Removes entries whose value is `null` from [source] and nested maps/lists.
  static Map<String, dynamic> omitNullEntriesDeep(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is Map<String, dynamic>) {
        sanitized[entry.key] = omitNullEntriesDeep(value);
      } else if (value is Map) {
        sanitized[entry.key] = omitNullEntriesDeep(Map<String, dynamic>.from(value));
      } else if (value is List<dynamic>) {
        sanitized[entry.key] = _omitNullEntriesInList(value);
      } else {
        sanitized[entry.key] = value;
      }
    }
    return sanitized;
  }

  static List<dynamic> _omitNullEntriesInList(List<dynamic> source) {
    final sanitized = <dynamic>[];
    for (final dynamic item in source) {
      if (item == null) {
        continue;
      }
      if (item is Map<String, dynamic>) {
        sanitized.add(omitNullEntriesDeep(item));
      } else if (item is Map) {
        sanitized.add(omitNullEntriesDeep(Map<String, dynamic>.from(item)));
      } else if (item is List<dynamic>) {
        sanitized.add(_omitNullEntriesInList(item));
      } else {
        sanitized.add(item);
      }
    }
    return sanitized;
  }

  /// Preserve required nullable journal fields; null means indeterminate, never zero.
  static Map<String, dynamic> _sanitizeResult(Map<String, dynamic> result) {
    // sourceSchema v1 has required nullable fields: schema, native metadata and nextOffset.
    // Their absence must not be confused with an observation of null/unknown.
    if (result['contractVersion'] == 1 &&
        result['identity'] is Map &&
        result['resources'] is List &&
        result['metadataPage'] is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {
      ...omitNullEntriesDeep(result),
      // I/O event schemas carry explicit nullable exit/progress observations.
      if (result['execution_id'] is String &&
          result['next_sequence'] is int &&
          result['terminal'] is bool &&
          result['output_complete'] is bool &&
          result['events'] is List)
        'events': result['events'],
      // An unsuccessful I/O lookup requires an explicit null execution identity.
      if (result['found'] == false &&
          result['reason'] == 'not_found_in_retention_window' &&
          result.containsKey('execution_id') &&
          result['execution_id'] == null)
        'execution_id': null,
      // A null receipt count means unknown delivery, not an omitted property.
      if (result['execution_id'] is String &&
          result['message_id'] is String &&
          result['sequence'] is int &&
          result.containsKey('confirmed_bytes') &&
          result['confirmed_bytes'] == null)
        'confirmed_bytes': null,
      // SQL null is a cell value. Removing it loses a column or shifts array cells.
      if (result['rows'] is List && (result['row_count'] is int || result['columns'] is List)) 'rows': result['rows'],
      if (result['multi_result'] == true)
        for (final key in ['result_sets', 'items'])
          if (result[key] is List)
            key: (result[key] as List<dynamic>)
                .map((dynamic item) => item is Map<String, dynamic> ? _sanitizeResult(item) : item)
                .toList(growable: false),
      if (result.containsKey('directlyAffectedRows') && result['directlyAffectedRows'] == null)
        'directlyAffectedRows': null,
    };
  }

  /// Strips `null` values from a prepared `rpc:response` wire object (single or batch).
  static dynamic sanitizeRpcResponseWirePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return _sanitizeRpcResponseWireMap(payload);
    }
    if (payload is List<dynamic>) {
      return payload
          .map(
            (dynamic item) => item is Map<String, dynamic> ? _sanitizeRpcResponseWireMap(item) : item,
          )
          .toList(growable: false);
    }
    return payload;
  }

  static Map<String, dynamic> _sanitizeRpcResponseWireMap(Map<String, dynamic> wire) {
    final sanitized = Map<String, dynamic>.from(wire);
    final result = sanitized['result'];
    if (result is Map<String, dynamic>) {
      sanitized['result'] = _sanitizeResult(result);
    } else if (result is Map) {
      sanitized['result'] = _sanitizeResult(Map<String, dynamic>.from(result));
    }
    return sanitized;
  }

  /// Removes `null` optional fields from an [RpcResponse] `result` before replay/cache use.
  static RpcResponse sanitizeRpcResponse(RpcResponse response) {
    final result = response.result;
    if (result is! Map<String, dynamic>) {
      return response;
    }
    return RpcResponse(
      jsonrpc: response.jsonrpc,
      id: response.id,
      result: _sanitizeResult(result),
      error: response.error,
      apiVersion: response.apiVersion,
      meta: response.meta,
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';

/// Normalizes one ODBC cell for JSON/RPC wire consumers.
///
/// SQL Anywhere may return lazy strings, binary payloads, and native timestamps
/// that must be materialized before JSON encoding.
Object? normalizeOdbcWireCell(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is LazyString) {
    return value.value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  if (value is List<int>) {
    return base64Encode(value);
  }
  return value;
}

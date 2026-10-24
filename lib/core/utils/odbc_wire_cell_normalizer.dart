import 'dart:convert';
import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';

/// Whether [normalizeOdbcWireCell] replaces [value] with a different object.
///
/// Plain JSON values stay the same instance, so a caller can keep the original
/// row instead of copying it or sending it through an isolate.
bool odbcWireCellNeedsMaterialization(Object? value) {
  return value is LazyString || value is DateTime || value is List<int>;
}

/// Normalizes one ODBC cell for JSON/RPC wire consumers.
///
/// SQL Anywhere may return lazy strings, binary payloads, and native timestamps
/// that must be materialized before JSON encoding.
Object? normalizeOdbcWireCell(Object? value) {
  // SQL cells are usually null, text, or numbers. Those return before the
  // generic List<int> test, which is the expensive check on this path.
  if (value == null || value is String || value is num || value is bool) {
    return value;
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

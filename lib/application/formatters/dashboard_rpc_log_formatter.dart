import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/core/utils/sql_rpc_log_payload_compactor.dart';

/// Max chars for formattedData before truncation to avoid heavy UI work.
const int dashboardRpcLogMaxFormattedDataChars = 8000;

bool dashboardRpcLogPreferCompactFormat(String event) {
  return event.startsWith('rpc:') || event.startsWith('agent:') || event == 'hub:heartbeat_ack';
}

/// Lightweight dashboard text for high-frequency hub sql.execute socket events.
/// Avoids walking/encoding full row payloads and expensive JSON pretty-printing.
class DashboardRpcLogFormatter {
  const DashboardRpcLogFormatter._();

  static String? formattedPreview(String event, dynamic data) {
    if (data is! Map) {
      return null;
    }
    switch (event) {
      case 'rpc:chunk':
        final rows = data['rows'];
        final rowCount = rows is List ? rows.length : 0;
        return 'chunk_index=${data['chunk_index']} rows=$rowCount '
            '(row payload omitted from dashboard feed)';
      case 'rpc:complete':
        return 'stream_id=${data['stream_id']} total_rows=${data['total_rows']}'
            '${data['terminal_status'] != null ? ' terminal_status=${data['terminal_status']}' : ''}';
      case 'rpc:response':
        return SqlRpcLogPayloadCompactor.rpcResponsePreview(data);
      case 'rpc:request':
        final method = data['method'];
        if (method != 'sql.execute') {
          return null;
        }
        final params = data['params'];
        if (params is! Map) {
          return null;
        }
        final sql = params['sql'];
        if (sql is! String) {
          return null;
        }
        final clipped = sql.length > 160 ? '${sql.substring(0, 160)}...' : sql;
        return 'method=$method id=${data['id']}\nsql: $clipped';
      default:
        return null;
    }
  }

  static Map<String, dynamic> dataSnapshot(String event, dynamic data) {
    return SqlRpcLogPayloadCompactor.dashboardDataSnapshot(event, data);
  }

  static String computeFormattedData(dynamic data, {required String event}) {
    try {
      String raw;
      if (data is Map || data is List) {
        final compact = jsonEncode(data);
        raw = dashboardRpcLogPreferCompactFormat(event) || compact.length > dashboardRpcLogMaxFormattedDataChars
            ? compact
            : const JsonEncoder.withIndent('  ').convert(data);
      } else {
        raw = data.toString();
      }
      if (raw.length > dashboardRpcLogMaxFormattedDataChars) {
        return '${raw.substring(0, dashboardRpcLogMaxFormattedDataChars)}\n'
            '... [truncated, ${raw.length} chars]';
      }
      return raw;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'WebSocket message format failed',
        name: 'dashboard_rpc_log_formatter',
        level: 700,
        error: e,
        stackTrace: stackTrace,
      );
      return '[Unable to format]';
    }
  }
}

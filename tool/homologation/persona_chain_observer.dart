import 'dart:convert';
import 'dart:io';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:result_dart/result_dart.dart';

class ChainFixtureObserver implements IRpcRequestDispatcher {
  const ChainFixtureObserver(this.delegate, this.metadata);
  final IRpcRequestDispatcher delegate;
  final File metadata;
  @override
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    final response = await delegate.dispatch(
      request,
      agentId,
      clientToken: clientToken,
      streamEmitter: streamEmitter,
      limits: limits,
      negotiatedExtensions: negotiatedExtensions,
    );
    final data = response.error?.data;
    final Object? params = request.params;
    final Object? structure = params is Map ? params['expectedStructure'] : null;
    final Object? resources = structure is Map ? structure['resources'] : null;
    await metadata.writeAsString(
      '${jsonEncode({
        'method': request.method,
        'code': response.error?.code,
        if (resources is List) 'structureResourceCount': resources.length,
        if (data is Map) ...{
          for (final key in ['failure_code', 'stage', 'retryable', 'outcome_unknown', 'reason'])
            if (data.containsKey(key)) key: data[key],
        },
        if (response.result is Map) 'resultKeys': (response.result as Map).keys.toList(),
        if (request.method == 'sql.execute' && response.result is Map) ...{
          'columnMetadata': (response.result as Map)['column_metadata'],
          'rowCount': (response.result as Map)['row_count'],
          'truncated': (response.result as Map)['truncated'],
          'effectiveMaxRows': (response.result as Map)['effective_max_rows'],
          'rowShapes': [
            for (final row in ((response.result as Map)['rows'] as List<dynamic>?) ?? [])
              if (row is Map) {
                  'keys': row.keys.toList(),
                  'cellTypes': row.values.map((v) => v.runtimeType.toString()).toList(),
                  'cellLengths': row.values.map((v) => v is String ? v.length : null).toList(),
                },
          ],
        },
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
    return response;
  }

  @override
  Future<void> cancelActiveStreamOnDisconnect() => delegate.cancelActiveStreamOnDisconnect();
  @override
  Future<Result<void>> cancelActiveSqlOnDisconnect() => delegate.cancelActiveSqlOnDisconnect();
}

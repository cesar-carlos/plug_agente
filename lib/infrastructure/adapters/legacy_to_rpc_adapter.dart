import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/models/envelope_model.dart';

/// Adapter for converting between legacy envelope protocol and RPC protocol.
class LegacyToRpcAdapter {
  /// Converts a legacy envelope to an RPC request.
  static RpcRequest envelopeToRpcRequest(EnvelopeModel envelope) {
    final payload = envelope.payloadBytes.isNotEmpty
        ? envelope.payloadBytes.first
        : <String, dynamic>{};

    final sql = payload['query'] as String? ?? '';
    final params = payload['parameters'] as Map<String, dynamic>?;

    return RpcRequest(
      jsonrpc: '2.0',
      method: 'sql.execute',
      id: envelope.requestId,
      params: {
        'sql': sql,
        'params': params,
      },
    );
  }

  /// Converts a QueryRequest to an RPC request.
  static RpcRequest queryRequestToRpcRequest(QueryRequest request) {
    return RpcRequest(
      jsonrpc: '2.0',
      method: 'sql.execute',
      id: request.id,
      params: {
        'sql': request.query,
        if (request.parameters != null) 'params': request.parameters,
      },
    );
  }

  /// Converts an RPC response to a QueryResponse.
  static QueryResponse rpcResponseToQueryResponse(
    RpcResponse response,
    String agentId,
  ) {
    if (response.isError) {
      // Convert error to QueryResponse with error field
      final error = response.error!;
      return QueryResponse(
        id: response.id?.toString() ?? '',
        requestId: response.id?.toString() ?? '',
        agentId: agentId,
        data: const [],
        timestamp: DateTime.now(),
        error: error.message,
      );
    }

    // Extract result data
    final result = response.result as Map<String, dynamic>;
    final rows = result['rows'] as List<dynamic>?;
    final affectedRows = result['affected_rows'] as int?;
    final columnMetadata = result['column_metadata'] as List<dynamic>?;

    return QueryResponse(
      id: result['execution_id'] as String? ?? '',
      requestId: response.id?.toString() ?? '',
      agentId: agentId,
      data: rows?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      affectedRows: affectedRows,
      timestamp: DateTime.now(),
      columnMetadata: columnMetadata
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }

  /// Converts an RPC response to a legacy envelope.
  static EnvelopeModel rpcResponseToEnvelope(
    RpcResponse response,
    String agentId,
  ) {
    final queryResponse = rpcResponseToQueryResponse(response, agentId);

    return EnvelopeModel(
      v: 1,
      type: 'query_response',
      requestId: queryResponse.requestId,
      agentId: agentId,
      timestamp: queryResponse.timestamp,
      cmp: 'none',
      contentType: 'json',
      payloadBytes: queryResponse.data,
    );
  }
}

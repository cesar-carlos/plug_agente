import 'package:plug_agente/domain/protocol/protocol.dart';

/// Outcome of database streaming attempt from sql.execute handler path.
final class SqlDbStreamingTryResult {
  const SqlDbStreamingTryResult({this.response, this.skipReason});

  final RpcResponse? response;
  final String? skipReason;

  bool get succeeded => response != null;
}

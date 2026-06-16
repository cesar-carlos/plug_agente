import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';

/// Tracks one in-flight ODBC streaming execution for cancel routing and cleanup.
final class OdbcStreamingActiveConnection {
  OdbcStreamingActiveConnection({
    required this.executionId,
    required this.connectionId,
    required this.lease,
  });

  final String executionId;
  final String connectionId;
  final DirectOdbcConnectionLease lease;
  bool isCancelRequested = false;
  bool isDisconnectStarted = false;
  StreamingCancelReason cancelReason = StreamingCancelReason.user;
}

import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_delivery_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_capabilities_lifecycle_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/socket_io_transport_connection_error_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_local_capabilities_builder.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_socket_event_binder.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

/// RPC transport pipeline components assembled for the v2 Socket.IO transport client.
final class TransportRpcPipelineBundle {
  TransportRpcPipelineBundle({
    required this.localCapabilitiesBuilder,
    required this.connectionErrorHandler,
    required this.pipelineCache,
    required this.frameCodec,
    required this.responsePreparer,
    required this.capabilitiesNegotiator,
    required this.authorizationDecisionLogger,
    required this.streamPullHandler,
    required this.inboundHandler,
    required this.rpcResponseDeliveryCoordinator,
    required this.capabilitiesLifecycleHandler,
    required this.socketEventBinder,
    required this.requestGuard,
    required this.schemaValidator,
    required this.contractValidator,
  });

  final TransportLocalCapabilitiesBuilder localCapabilitiesBuilder;
  final SocketIoTransportConnectionErrorHandler connectionErrorHandler;
  final TransportPipelineCache pipelineCache;
  final PayloadFrameCodec frameCodec;
  final RpcResponsePreparer responsePreparer;
  final CapabilitiesNegotiator capabilitiesNegotiator;
  final AuthorizationDecisionLogger authorizationDecisionLogger;
  final RpcStreamPullHandler streamPullHandler;
  final RpcInboundHandler inboundHandler;
  final RpcResponseDeliveryCoordinator rpcResponseDeliveryCoordinator;
  final SocketIoCapabilitiesLifecycleHandler capabilitiesLifecycleHandler;
  final TransportSocketEventBinder socketEventBinder;
  final RpcRequestGuard requestGuard;
  final RpcRequestSchemaValidator schemaValidator;
  final RpcContractValidator contractValidator;
}

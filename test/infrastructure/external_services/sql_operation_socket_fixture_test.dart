import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/sql_operation_rpc_handler.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/codecs/transport_work_pool.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_runtime.dart';
import 'package:result_dart/result_dart.dart';
import '../../application/services/sql_operation_executor_test.dart' show Authorizer, Transactions;

class _Dispatcher implements IRpcRequestDispatcher {
  _Dispatcher(this.executor);
  final SqlOperationExecutor executor;
  final finished = Completer<void>();
  int calls = 0;
  @override
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    final response = await SqlOperationRpcHandler(request.method, executor, enabled: () => true).handle(
      request,
      RpcDispatchContext(
        agentId: agentId,
        clientToken: clientToken,
        streamEmitter: streamEmitter,
        limits: limits ?? const TransportLimits(),
        negotiatedExtensions: negotiatedExtensions,
      ),
    );
    if (++calls == 8) finished.complete();
    return response;
  }

  @override
  Future<void> cancelActiveStreamOnDisconnect() async {}
  @override
  Future<Result<void>> cancelActiveSqlOnDisconnect() async => const Success(unit);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['PLUG_SQL_OPERATION_E2E_URL'];
  test(
    'production socket negotiation reaches durable journal without replaying uncertain commit',
    () async {
      final directory = await Directory.systemTemp.createTemp('sql-operation-socket-');
      final runtime = SqlOperationJournalRuntime('${directory.path}/journal.db');
      final transactions = Transactions()..loseCommit = true;
      (await runtime.initialize()).getOrThrow();
      final dispatcher = _Dispatcher(
        SqlOperationExecutor(
          journal: runtime.journal,
          authorizer: Authorizer(),
          transactions: transactions,
        ),
      );
      final flags = FeatureFlags(
        InMemoryAppSettingsStore({
          'feature_enable_sql_operations': true,
          'feature_enable_agent_actions': false,
          'feature_enable_remote_agent_actions': false,
        }),
      );
      final transport = SocketIOTransportClientV2(
        dataSource: SocketDataSource(),
        negotiator: ProtocolNegotiator(),
        rpcDispatcher: dispatcher,
        featureFlags: flags,
      );
      try {
        final connected = await transport.connect(url!, 'agent-operation-test', authToken: 'test-only-token');
        expect(connected.isSuccess(), isTrue);
        await dispatcher.finished.future.timeout(const Duration(seconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(transactions.opened, 1);
        expect(transactions.commits, 1);
        expect(transactions.executed.length, 2);
        expect(transactions.bindings[1]['parent_id']?.value, '42');
      } finally {
        await transport.disconnect();
        await TransportWorkPool.shared.dispose();
        await runtime.close();
        await directory.delete(recursive: true);
      }
    },
    skip: url == null ? 'Run through the isolated Node socket harness.' : false,
    timeout: const Timeout(Duration(seconds: 35)),
  );
}

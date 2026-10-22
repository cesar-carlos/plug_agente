import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

import '../../tool/homologation/persona_chain_observer.dart';

class _Dispatcher extends Fake implements IRpcRequestDispatcher {
  bool fail = false;

  @override
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    if (fail) throw StateError('fixture delegate failure');
    return RpcResponse.success(id: request.id, result: {'complete': true});
  }
}

void main() {
  late Directory root;
  late File metadata;
  late _Dispatcher delegate;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('persona_observer_test_');
    metadata = File('${root.path}/rpc.jsonl');
    delegate = _Dispatcher();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('concurrent responses keep every metadata record intact', () async {
    final observer = ChainFixtureObserver(delegate, metadata);
    final requests = List.generate(
      256,
      (index) => RpcRequest(jsonrpc: '2.0', id: index, method: 'fixture.$index'),
    );
    final responses = await Future.wait([
      for (final request in requests) observer.dispatch(request, 'fixture-agent'),
    ]);
    final records = (await metadata.readAsLines()).map((line) => jsonDecode(line) as Map<String, dynamic>).toList();
    expect(records, hasLength(requests.length));
    expect(records.map((record) => record['method']).toSet(), requests.map((request) => request.method).toSet());
    expect(responses.map((response) => response.id), requests.map((request) => request.id));
  });

  test('delegate failures are preserved without a success record', () async {
    delegate.fail = true;
    final observer = ChainFixtureObserver(delegate, metadata);
    await expectLater(
      observer.dispatch(const RpcRequest(jsonrpc: '2.0', id: 1, method: 'fixture.failure'), 'fixture-agent'),
      throwsStateError,
    );
    expect(metadata.existsSync(), isFalse);
  });

  test('metadata write failure is not converted into a successful RPC response', () async {
    await Directory(metadata.path).create();
    final observer = ChainFixtureObserver(delegate, metadata);
    await expectLater(
      observer.dispatch(const RpcRequest(jsonrpc: '2.0', id: 1, method: 'fixture.failure'), 'fixture-agent'),
      throwsA(isA<FileSystemException>()),
    );
  });
}

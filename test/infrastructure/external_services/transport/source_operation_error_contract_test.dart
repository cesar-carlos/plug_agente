import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/source_discovery_rpc_handler.dart';
import 'package:plug_agente/application/rpc/source_schema_rpc_handler.dart';
import 'package:plug_agente/application/rpc/sql_operation_rpc_handler.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/protocol/sql_operation_capability.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

class _Flags extends Mock implements FeatureFlags {}

class _Configs extends Mock implements IQueryConfigSource {}

class _Tokens extends Mock implements ClientTokenValidationService {}

class _DiscoveryProbe extends Mock implements ISourceDiscoveryProbe {}

class _SchemaProbe extends Mock implements ISourceSchemaProbe {}

class _Executor extends Mock implements SqlOperationExecutor {}

class _Reference extends Fake implements SqlOperationReference {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransportSchemaLoader loader;
  late RpcResponsePreparer preparer;
  late _Executor executor;
  late _Tokens tokens;
  late Map<String, RpcMethodHandler> handlers;

  setUpAll(() => registerFallbackValue(_Reference()));
  setUp(() async {
    final flags = _Flags();
    when(() => flags.enableSocketSchemaValidation).thenReturn(true);
    when(() => flags.enableSocketOutgoingContractValidation).thenReturn(true);
    when(() => flags.enableSocketApiVersionMeta).thenReturn(true);
    loader = TransportSchemaLoader();
    await loader.loadAll();
    expect(loader.get(TransportSchemaIds.rpcError), isNotNull);
    expect(loader.get(TransportSchemaIds.rpcResponse), isNotNull);
    expect(loader.get(TransportSchemaIds.rpcBatchResponse), isNotNull);
    preparer = RpcResponsePreparer(
      featureFlags: flags,
      logSummarizer: PayloadLogSummarizer(thresholdBytes: 8192),
      contractValidator: const RpcContractValidator(),
      protocolProvider: () => const ProtocolConfig(protocol: 'jsonrpc-v2', encoding: 'json', compression: 'gzip'),
      usesBinaryTransport: () => true,
      agentIdProvider: () => 'agent',
      jsonSchemaValidator: JsonSchemaContractValidator(loader: loader),
    );
    executor = _Executor();
    tokens = _Tokens();
    final configs = _Configs();
    handlers = {
      'sql.describeSource': SourceDiscoveryRpcHandler(configs, tokens, _DiscoveryProbe()),
      'sql.describeSchema': SourceSchemaRpcHandler(configs, tokens, _SchemaProbe()),
      for (final method in ['sql.operation.execute', 'sql.operation.get', 'sql.operation.cancel'])
        method: SqlOperationRpcHandler(method, executor, enabled: () => true),
    };
  });

  Future<Map<String, dynamic>> response(
    String method,
    Object? id, {
    Map<String, dynamic> extensions = const {},
    Object? params,
  }) async {
    final request = RpcRequest(
      jsonrpc: '2.0',
      method: method,
      id: id,
      params: params,
      meta: const RpcProtocolMeta(requestId: 'hub-request', traceId: 'trace'),
    );
    final result = await handlers[method]!.handle(
      request,
      RpcDispatchContext(
        agentId: 'agent',
        clientToken: 'token',
        streamEmitter: null,
        limits: const TransportLimits(),
        negotiatedExtensions: extensions,
      ),
    );
    return preparer.prepareForSend(preparer.attachRequestTrace(request, result));
  }

  void expectError(Map<String, dynamic> wire, Object? id, String failureCode, int rpcCode) {
    expect(wire['id'], id);
    final error = wire['error'] as Map<String, dynamic>;
    expect(error['code'], rpcCode);
    expect(loader.get(TransportSchemaIds.rpcError)!.validate(error).isValid, isTrue);
    final data = error['data'] as Map<String, dynamic>;
    expect(data['failure_code'], failureCode);
    expect(data['retryable'], isFalse);
    expect(data['correlation_id'], 'hub-request');
    expect((wire['meta'] as Map)['request_id'], 'hub-request');
    expect((wire['meta'] as Map)['trace_id'], 'trace');
    expect(jsonEncode(wire), isNot(contains('private-driver-secret')));
  }

  const deniedCodes = {
    'sql.describeSource': 'SOURCE_DISCOVERY_UNAVAILABLE',
    'sql.describeSchema': 'VALIDATION_ERROR',
    'sql.operation.execute': 'CAPABILITY_UNAVAILABLE',
    'sql.operation.get': 'CAPABILITY_UNAVAILABLE',
    'sql.operation.cancel': 'CAPABILITY_UNAVAILABLE',
  };
  for (final entry in deniedCodes.entries) {
    for (final id in <Object>['consumer-request', 0]) {
      test('${entry.key} refusal retains $id through outgoing validation', () async {
        final wire = await response(entry.key, id);
        final validated = preparer.validateOutgoing(wire, methodsById: {id: entry.key}).getOrThrow();
        expectError(validated as Map<String, dynamic>, id, entry.value, -32000);
      });
    }
  }

  test('mixed batch retains every refusal, ID and successful sibling', () async {
    final wires = <Map<String, dynamic>>[];
    var id = 0;
    for (final method in deniedCodes.keys) {
      wires.add(await response(method, id++));
    }
    wires.add(preparer.prepareForSend(RpcResponse.success(id: 'success', result: {'ok': true})));
    final validated = preparer.validateOutgoing(wires).getOrThrow();
    expect(validated, isA<List<dynamic>>());
    final batch = validated as List<dynamic>;
    expect(batch.length, wires.length);
    id = 0;
    for (final code in deniedCodes.values) {
      expectError(batch[id] as Map<String, dynamic>, id, code, -32000);
      id++;
    }
    expect(batch.last, wires.last);
  });

  test('operation parameter errors retain invalid-params classification', () async {
    final wire = await response(
      'sql.operation.execute',
      'invalid',
      extensions: {SqlOperationCapability.key: SqlOperationCapability.advertisement},
      params: <String, dynamic>{},
    );
    final original = wire['error'] as Map<String, dynamic>;
    final failureCode = (original['data'] as Map)['failure_code'] as String;
    expectError(
      preparer.validateOutgoing(wire).getOrThrow() as Map<String, dynamic>,
      'invalid',
      failureCode,
      RpcErrorCode.invalidParams,
    );
    verifyZeroInteractions(executor);
  });

  test('source discovery exceptions remain safe and correlated', () async {
    when(() => tokens.validate('token')).thenThrow(StateError('private-driver-secret'));
    final wire = await response(
      'sql.describeSource',
      'probe',
      extensions: {'sourceDiscovery': 1},
      params: {'contractVersion': 1, 'database': 'test_db'},
    );
    expectError(
      preparer.validateOutgoing(wire).getOrThrow() as Map<String, dynamic>,
      'probe',
      'SOURCE_DISCOVERY_UNAVAILABLE',
      -32000,
    );
    verify(() => tokens.validate('token')).called(1);
  });

  test('schema inspection exceptions remain safe and correlated', () async {
    when(() => tokens.validate('token')).thenThrow(StateError('private-driver-secret'));
    final wire = await response(
      'sql.describeSchema',
      'schema',
      extensions: {'sourceSchema': 1, 'sourceIdentity': 1},
      params: {
        'contractVersion': 1,
        'database': 'test_db',
        'offset': 0,
        'pageSize': 1,
        'expectedSource': {'version': 1, 'dialect': 'postgres', 'identityHash': 'a' * 64},
        'resources': [
          {'schema': 'public', 'name': 'example', 'type': 'table'},
        ],
      },
    );
    expectError(
      preparer.validateOutgoing(wire).getOrThrow() as Map<String, dynamic>,
      'schema',
      'SOURCE_SCHEMA_UNAVAILABLE',
      -32000,
    );
    verify(() => tokens.validate('token')).called(1);
  });

  test('errors without request metadata use the original ID for correlation', () async {
    for (final handler in handlers.values) {
      final result = await handler.handle(
        RpcRequest(jsonrpc: '2.0', method: handler.method, id: 0),
        const RpcDispatchContext(
          agentId: 'agent',
          clientToken: null,
          streamEmitter: null,
          limits: TransportLimits(),
          negotiatedExtensions: {},
        ),
      );
      final wire = preparer.validateOutgoing(preparer.prepareForSend(result)).getOrThrow() as Map<String, dynamic>;
      expect(wire['id'], 0);
      expect(((wire['error'] as Map)['data'] as Map)['correlation_id'], '0');
    }
  });

  for (final throwsError in [false, true]) {
    test('operation ${throwsError ? 'exception' : 'failure'} remains safe and correlated', () async {
      final stub = when(() => executor.get(any(), 'token', 'agent'));
      if (throwsError) {
        stub.thenThrow(StateError('private-driver-secret'));
      } else {
        stub.thenAnswer(
          (_) async => Failure(
            SqlOperationFailure(
              code: 'SQL_OPERATION_AUTHORIZATION_DENIED',
              message: 'private-driver-secret',
              context: {'password': 'private-driver-secret'},
            ),
          ),
        );
      }
      final wire = await response(
        'sql.operation.get',
        'lookup',
        extensions: {SqlOperationCapability.key: SqlOperationCapability.advertisement},
        params: {
          'contractVersion': 1,
          'operationId': '00000000-0000-4000-8000-000000000001',
          'fingerprint': 'a' * 64,
          'sourcePhysicalId': 'b' * 64,
          'database': 'test_db',
        },
      );
      expectError(
        preparer.validateOutgoing(wire).getOrThrow() as Map<String, dynamic>,
        'lookup',
        throwsError ? 'SQL_OPERATION_FAILED' : 'SQL_OPERATION_AUTHORIZATION_DENIED',
        throwsError ? RpcErrorCode.internalError : -32000,
      );
      verify(() => executor.get(any(), 'token', 'agent')).called(1);
    });
  }
}

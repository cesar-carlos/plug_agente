import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/source_discovery_rpc_handler.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

import '../services/sql_operation_executor_test.dart' show fixtureConfig;

class _Policies extends Mock implements IAuthorizationPolicyResolver {}

class _Configs extends Mock implements IQueryConfigSource {}

class _Probe implements ISourceDiscoveryProbe {
  void Function()? after;
  int calls = 0;
  @override
  Future<Result<SourceDiscovery>> inspect(Config config, String database) async {
    calls++;
    after?.call();
    return Success(
      SourceDiscovery(
        database: database,
        dialect: 'postgres',
        identityHash: 'a' * 64,
        identityKind: 'native',
        engineVersion: 'fixture',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ClientTokenPolicy policy(bool revoked, {String database = 'test_db'}) => ClientTokenPolicy(
    clientId: 'client',
    agentId: 'agent',
    allTables: false,
    allViews: false,
    globalPermissions: const ClientPermissionSet(canRead: false, canUpdate: false, canDelete: false),
    rules: const [],
    payload: {'database': database},
    isRevoked: revoked,
  );
  test('discovery checks token/config before and after native inspection; does not license business reads', () async {
    final policies = _Policies();
    final configs = _Configs();
    final probe = _Probe();
    var revoked = false;
    var config = fixtureConfig.copyWith(agentId: 'agent');
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy(revoked)));
    when(configs.resolveActiveConfig).thenAnswer((_) async => Success(config));
    final handler = SourceDiscoveryRpcHandler(configs, ClientTokenValidationService(policies), probe);
    Future<RpcResponse> call({int capability = 1, Map<String, dynamic>? params}) => handler.handle(
      RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.describeSource',
        id: 'request',
        params: params ?? {'contractVersion': 1, 'database': 'test_db', 'client_token': 'token'},
      ),
      RpcDispatchContext(
        agentId: 'agent',
        clientToken: 'token',
        streamEmitter: null,
        limits: const TransportLimits(),
        negotiatedExtensions: {'sourceDiscovery': capability},
      ),
    );
    expect((await call()).result, isA<Map<String, dynamic>>());
    expect((await call(capability: 2)).error, isNotNull);
    expect(
      (await call(params: {'contractVersion': 1, 'database': 'test_db', 'sql': 'SELECT secret'})).error,
      isNotNull,
    );
    expect(probe.calls, 1);
    probe.after = () => revoked = true;
    expect((await call()).error, isNotNull);
    revoked = false;
    probe.after = () => config = config.copyWith(host: 'another-host');
    expect((await call()).error, isNotNull);
  });
  test('published schemas reject arbitrary SQL and incomplete physical proof', () async {
    final loader = TransportSchemaLoader();
    await loader.loadAll();
    const catalog = RpcMethodSchemaCatalog();
    final params = loader.get(catalog.paramsSchemaFor('sql.describeSource')!)!;
    final result = loader.get(catalog.resultSchemaFor('sql.describeSource')!)!;
    expect(params.validate({'contractVersion': 1, 'database': 'test_db', 'client_token': 'token'}).isValid, isTrue);
    expect(params.validate({'contractVersion': 1, 'database': 'test_db', 'sql': 'SELECT anything'}).isValid, isFalse);
    expect(result.validate({'contractVersion': 1, 'database': 'test_db', 'dialect': 'postgres'}).isValid, isFalse);
  });
}

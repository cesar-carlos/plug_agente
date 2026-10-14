import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/rpc/source_discovery_rpc_handler.dart';
import 'package:plug_agente/application/rpc/source_schema_rpc_handler.dart';
import 'package:plug_agente/application/rpc/sql_operation_rpc_handler.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_operation_authorizer.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/infrastructure/codecs/transport_work_pool.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_runtime.dart';
import 'package:uuid/uuid.dart';
import 'persona_chain_cases.dart';
import 'persona_chain_faults.dart';
import 'persona_chain_observer.dart';
import 'persona_chain_storage.dart';

// Explicit isolated fixture only; production config and native vault adapters.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifestPath = Platform.environment['PERSONA_CHAIN_AGENT_MANIFEST'];
  if (manifestPath == null) throw StateError('Explicit private chain manifest is mandatory.');
  final manifest = jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  final runId = manifest['runId'] as String;
  final root = Directory(manifest['root'] as String).resolveSymbolicLinksSync();
  final hubUrl = manifest['hubUrl'] as String;
  final sessionRoot = Directory(manifest['sessionRoot'] as String).resolveSymbolicLinksSync();
  if (Directory(sessionRoot).parent.path != root ||
      !RegExp(r'^chain-[a-f0-9]{32}$').hasMatch(sessionRoot.split(Platform.pathSeparator).last)) {
    throw StateError('Invalid fixture session root.');
  }
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
      !root.endsWith('${Platform.pathSeparator}$runId') ||
      Uri.parse(hubUrl).host != '127.0.0.1') {
    throw StateError('Only loopback, explicitly named fixture environments are accepted.');
  }
  test('four real engines through production RPC, policy, socket and journal', () async {
    registerChainVault(Directory(sessionRoot));
    final locator = odbc.ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 4);
    final service = locator.asyncService;
    (await service.initialize()).getOrThrow();
    final cleanup = <Future<void> Function()>[];
    final ready = <String, Object>{};
    final evaluators = <String, Future<bool> Function(Map<String, dynamic>)>{};
    try {
      for (final engine in ['postgres', 'mssql', 'sybase', 'firebird']) {
        final fixture = (manifest['engines'] as Map<String, dynamic>)[engine] as Map<String, dynamic>;
        final database = fixture['database'] as String;
        if (engine == 'firebird'
            ? File(database).absolute.path != '$root${Platform.pathSeparator}$runId.fdb'
            : database != runId) {
          throw StateError('Business fixture database mismatch: $engine');
        }
        final storage = ChainAgentStorage(sessionRoot, engine);
        cleanup.add(storage.database.close);
        final resumed = storage.resumed;
        final connection = resumed ? '' : fixture['connectionString'] as String;
        if (!resumed) {
          final setupId = (await service.connect(connection)).getOrThrow().id;
          try {
            final actual = (await service.executeQuery(
              engine == 'postgres'
                  ? 'SELECT CURRENT_DATABASE()'
                  : engine == 'firebird'
                  ? r'SELECT MON$DATABASE_NAME FROM MON$DATABASE'
                  : 'SELECT DB_NAME()',
              connectionId: setupId,
            )).getOrThrow().rows.single.single.toString();
            if (engine == 'firebird'
                ? File(actual).absolute.path.toLowerCase() != File(database).absolute.path.toLowerCase()
                : actual != database) {
              throw StateError('Actual private fixture database mismatch.');
            }
            final exists =
                engine != 'firebird' ||
                (await service.executeQuery(
                      r"SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = 'OPERATION_FIXTURE'",
                      connectionId: setupId,
                    )).getOrThrow().rows.single.single !=
                    0;
            if (exists) {
              (await service.executeQuery(
                engine == 'firebird' ? 'DROP TABLE operation_fixture' : 'DROP TABLE IF EXISTS operation_fixture',
                connectionId: setupId,
              )).getOrThrow();
            }
            final generated = switch (engine) {
              'mssql' => 'INTEGER IDENTITY(1,1)',
              'sybase' => 'INTEGER DEFAULT AUTOINCREMENT',
              _ => 'INTEGER GENERATED BY DEFAULT AS IDENTITY',
            };
            (await service.executeQuery(
              'CREATE TABLE operation_fixture (id $generated PRIMARY KEY, marker VARCHAR(64) NOT NULL UNIQUE, amount DECIMAL(18,2) NOT NULL, revision INTEGER NOT NULL)',
              connectionId: setupId,
            )).getOrThrow();
            (await service.executeQuery(
              "INSERT INTO operation_fixture(marker, amount, revision) VALUES ('seed', 10.25, 1)",
              connectionId: setupId,
            )).getOrThrow();
            for (final sql in [
              'CREATE TABLE schema_parent (tenant_id INTEGER NOT NULL, item_id INTEGER NOT NULL, PRIMARY KEY(tenant_id,item_id))',
              'CREATE UNIQUE INDEX ux_schema_parent ON schema_parent(item_id,tenant_id)',
              'CREATE TABLE schema_child (tenant_id INTEGER NOT NULL, item_id INTEGER NOT NULL, PRIMARY KEY(tenant_id,item_id), CONSTRAINT fk_schema_parent FOREIGN KEY(tenant_id,item_id) REFERENCES schema_parent(tenant_id,item_id))',
            ]) {
              (await service.executeQuery(sql, connectionId: setupId)).getOrThrow();
            }
          } finally {
            (await service.disconnect(setupId)).getOrThrow();
          }
        }
        final config = await storage.open(
          Config(
            id: const Uuid().v4(),
            driverName: engine,
            odbcDriverName: engine,
            connectionString: connection,
            username: '',
            databaseName: database,
            host: '127.0.0.1',
            port: fixture['port'] as int,
            agentId: fixture['agentId'] as String,
            serverUrl: hubUrl,
            authToken: fixture['agentAuthToken'] as String?,
            refreshToken: fixture['agentRefreshToken'] as String?,
            nome: 'Isolated fixture',
            nomeFantasia: 'Isolated fixture',
            cnaeCnpjCpf: fixture['profileDocument'] as String,
            celular: '11988887777',
            email: 'fixture@example.com',
            endereco: 'Fixture',
            numeroEndereco: '1',
            bairro: 'Fixture',
            cep: '01001000',
            nomeMunicipio: 'Fixture',
            ufMunicipio: 'SP',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          manifest['clientId'] as String,
        );
        final settings = InMemoryAppSettingsStore({
          'feature_enable_sql_operations': true,
          'feature_enable_socket_auth': true,
          'feature_enable_agent_actions': false,
          'feature_enable_remote_agent_actions': false,
        });
        final flags = FeatureFlags(settings);
        final strings = ConfigService(ConfigValidator());
        final configs = storage.configs;
        final source = ActiveConfigResolver(configs, settings);
        final tokens = storage.tokens;
        final policy = AuthorizationPolicyResolver(flags, clientTokenRepository: tokens);
        final validation = ClientTokenValidationService(policy);
        final limiter = DirectOdbcConnectionLimiter(maxConcurrent: 2, acquireTimeout: const Duration(seconds: 5));
        final odbcSettings = OdbcConnectionSettings(settings);
        await odbcSettings.load();
        final metrics = MetricsCollector();
        final pool = OdbcConnectionPool(service, odbcSettings, metricsCollector: metrics);
        final gateway = OdbcDatabaseGateway(
          source,
          strings,
          service,
          pool,
          RetryManager(),
          metrics,
          odbcSettings,
          directConnectionLimiter: limiter,
          featureFlags: flags,
        );
        final journal = SqlOperationJournalRuntime('$sessionRoot/$engine-journal.sqlite');
        (await journal.initialize()).getOrThrow();
        cleanup.add(journal.close);
        final faultFactory = ChainCommitFaultFactory(OdbcSqlOperationTransactionFactory(service, strings, limiter));
        final executor = SqlOperationExecutor(
          journal: journal.journal,
          authorizer: SqlOperationAuthorizer(source, validation),
          transactions: faultFactory,
        );
        final caseAuthorizer = SqlOperationAuthorizer(source, validation);
        final caseFactory = OdbcSqlOperationTransactionFactory(service, strings, limiter);
        evaluators[engine] = (job) async {
          if (job['kind'] == 'lose-commit-confirmation') {
            faultFactory.loseNextConfirmation = true;
            return true;
          }
          if (job['kind'] == 'revoke-technical-token') {
            (await tokens.revokeToken(storage.tokenId)).getOrThrow();
            return true;
          }
          return evaluateChainCase(job, caseFactory, caseAuthorizer, storage.tokenValue, config.agentId);
        };
        final dispatcher = RpcMethodDispatcher(
          databaseGateway: gateway,
          healthService: HealthService(metricsCollector: metrics, gateway: gateway),
          normalizerService: QueryNormalizerService(QueryNormalizer()),
          uuid: const Uuid(),
          authorizeSqlOperation: AuthorizeSqlOperation(SqlOperationClassifier(), validation),
          getClientTokenPolicy: GetClientTokenPolicy(policy),
          getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 1000),
          featureFlags: flags,
          configRepository: configs,
          connectionStringSource: strings,
          additionalHandlers: [
            SourceDiscoveryRpcHandler(source, validation, OdbcSourceDiscovery(service, strings, limiter)),
            SourceSchemaRpcHandler(
              source,
              validation,
              OdbcSourceSchema(OdbcSourceDiscovery(service, strings, limiter)),
            ),
            for (final method in ['sql.operation.execute', 'sql.operation.get', 'sql.operation.cancel'])
              SqlOperationRpcHandler(method, executor, enabled: () => flags.enableSqlOperations),
          ],
        );
        final transport = SocketIOTransportClientV2(
          dataSource: SocketDataSource(),
          negotiator: ProtocolNegotiator(),
          rpcDispatcher: ChainFixtureObserver(dispatcher, File('$sessionRoot/$engine-rpc.jsonl')),
          featureFlags: flags,
        );
        cleanup.add(transport.disconnect);
        (await transport.connect(hubUrl, config.agentId, authToken: config.authToken)).getOrThrow();
        ready[engine] = {
          'agentId': config.agentId,
          'clientToken': storage.tokenValue,
          'tokenId': storage.tokenId,
          'configId': config.id,
          'resumed': resumed,
          'storage': 'drift-windows-dpapi',
        };
      }
      await File('$sessionRoot/agents-ready.json').writeAsString(jsonEncode(ready), flush: true);
      final deadline = DateTime.now().add(const Duration(minutes: 8));
      while (!File('$sessionRoot/agents-stop').existsSync()) {
        for (final item in Directory(
          sessionRoot,
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.case-job.json'))) {
          final job = jsonDecode(await item.readAsString()) as Map<String, dynamic>;
          var passed = false;
          String? code;
          try {
            passed = await evaluators[job['engine']]!(job);
          } on Object catch (error) {
            code = error is SqlOperationFailure ? error.code : error.runtimeType.toString();
            passed = false;
          }
          await File(
            '${item.path}.result',
          ).writeAsString(jsonEncode({'passed': passed, 'code': ?code}), flush: true);
          await item.rename('${item.path}.processed');
        }
        if (DateTime.now().isAfter(deadline)) throw StateError('Fixture controller did not finish.');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      for (final close in cleanup.reversed) {
        await close();
      }
      await TransportWorkPool.shared.dispose();
      locator.shutdown();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

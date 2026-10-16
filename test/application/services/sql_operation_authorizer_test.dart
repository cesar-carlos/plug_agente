import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_authorizer.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:result_dart/result_dart.dart';
import 'sql_operation_executor_test.dart' show envelope, fixtureConfig;

class Policies extends Mock implements IAuthorizationPolicyResolver {}

class Configs extends Mock implements IQueryConfigSource {}

void main() {
  late Policies policies;
  late Configs configs;
  late SqlOperationAuthorizer authorizer;
  ClientTokenPolicy policy({
    String? database = 'test_db',
    bool revoked = false,
    String agent = 'agent',
    ClientPermissionSet permissions = ClientPermissionSet.fullAccess,
  }) => ClientTokenPolicy(
    clientId: 'client',
    agentId: agent,
    allTables: true,
    allViews: true,
    globalPermissions: permissions,
    rules: const [],
    payload: {'database': ?database},
    isRevoked: revoked,
  );
  final physical = sha256.convert(utf8.encode(jsonEncode(['https://api.example.com', 'agent', 'test_db']))).toString();
  final raw = envelope()..['sourcePhysicalId'] = physical;
  final plan = const SqlOperationParamsReader().plan(raw);
  setUp(() {
    policies = Policies();
    configs = Configs();
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy()));
    when(
      () => configs.resolveActiveConfig(),
    ).thenAnswer((_) async => Success(fixtureConfig.copyWith(agentId: 'agent')));
    authorizer = SqlOperationAuthorizer(configs, ClientTokenValidationService(policies));
  });
  test('all write resources are authorized and INSERT maps to existing update permission', () async {
    final result = await authorizer.authorize(plan, 'token', 'agent', plan.steps);
    expect(result.isSuccess(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer(
      (_) async =>
          Success(policy(permissions: const ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false))),
    );
    expect((await authorizer.authorize(plan, 'token', 'agent', plan.steps)).isError(), isTrue);
  });
  test('structural dependencies require read permission in addition to write permission', () async {
    final identity = 'a' * 64;
    final raw = envelope()
      ..['sourcePhysicalId'] = sha256.convert(utf8.encode(jsonEncode(['https://api.example.com', identity]))).toString()
      ..['expectedSource'] = {'version': 1, 'dialect': 'postgres', 'identityHash': identity}
      ..['expectedStructure'] = {
        'version': 1,
        'resources': [
          {
            'resource': {'schema': 'public', 'name': 'parent', 'type': 'table'},
            'columns': [
              {'name': 'id', 'nativeType': 'int4', 'nullable': false, 'size': 32, 'scale': 0},
            ],
          },
        ],
      };
    final guarded = const SqlOperationParamsReader().plan(raw);
    when(() => policies.resolvePolicy(any())).thenAnswer(
      (_) async =>
          Success(policy(permissions: const ClientPermissionSet(canRead: false, canUpdate: true, canDelete: true))),
    );
    expect((await authorizer.authorize(guarded, 'token', 'agent', guarded.steps)).isError(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy()));
    expect((await authorizer.authorize(guarded, 'token', 'agent', guarded.steps)).isSuccess(), isTrue);
  });
  test('database binding is mandatory even for status and full access tokens', () async {
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy(database: null)));
    expect((await authorizer.authorize(plan, 'token', 'agent', const [])).isError(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy(database: 'other')));
    expect((await authorizer.authorize(plan, 'token', 'agent', const [])).isError(), isTrue);
  });
  test('policy, agent identity and physical source are rechecked without a decision cache', () async {
    expect((await authorizer.authorize(plan, 'token', 'agent', plan.steps)).isSuccess(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy(revoked: true)));
    expect((await authorizer.authorize(plan, 'token', 'agent', plan.steps)).isError(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy(agent: 'other')));
    expect((await authorizer.authorize(plan, 'token', 'agent', const [])).isError(), isTrue);
    when(() => policies.resolvePolicy(any())).thenAnswer((_) async => Success(policy()));
    when(
      () => configs.resolveActiveConfig(),
    ).thenAnswer((_) async => Success(fixtureConfig.copyWith(agentId: 'other')));
    expect((await authorizer.authorize(plan, 'token', 'agent', const [])).isError(), isTrue);
    when(() => configs.resolveActiveConfig()).thenAnswer(
      (_) async => Success(fixtureConfig.copyWith(agentId: 'agent', serverUrl: 'https://other.example.com')),
    );
    expect((await authorizer.authorize(plan, 'token', 'agent', const [])).isError(), isTrue);
  });
  test('credential change invalidates execution authority; technical tokens have distinct journal scopes', () async {
    final original = (await authorizer.authorize(plan, 'token', 'agent', const [])).getOrThrow();
    final another = (await authorizer.authorize(plan, 'another-token', 'agent', const [])).getOrThrow();
    expect(another.scopeHash, isNot(original.scopeHash));
    when(
      () => configs.resolveActiveConfig(),
    ).thenAnswer((_) async => Success(fixtureConfig.copyWith(agentId: 'agent', password: 'changed')));
    final changed = (await authorizer.authorize(plan, 'token', 'agent', const [])).getOrThrow();
    expect(changed.authorizationHash, isNot(original.authorizationHash));
    expect(changed.scopeHash, original.scopeHash);
    expect(changed.authorizationHash, isNot(contains('changed')));
  });
}

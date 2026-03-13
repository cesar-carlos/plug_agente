import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockCreateClientToken extends Mock implements CreateClientToken {}

class MockListClientTokens extends Mock implements ListClientTokens {}

class MockRevokeClientToken extends Mock implements RevokeClientToken {}

class MockDeleteClientToken extends Mock implements DeleteClientToken {}

void main() {
  setUpAll(() {
    registerFallbackValue(_buildRequest());
  });

  group('ClientTokenProvider', () {
    late MockCreateClientToken mockCreateClientToken;
    late MockListClientTokens mockListClientTokens;
    late MockRevokeClientToken mockRevokeClientToken;
    late MockDeleteClientToken mockDeleteClientToken;
    late ClientTokenProvider provider;

    setUp(() {
      mockCreateClientToken = MockCreateClientToken();
      mockListClientTokens = MockListClientTokens();
      mockRevokeClientToken = MockRevokeClientToken();
      mockDeleteClientToken = MockDeleteClientToken();
      provider = ClientTokenProvider(
        mockCreateClientToken,
        mockListClientTokens,
        mockRevokeClientToken,
        mockDeleteClientToken,
      );
    });

    test('should load tokens successfully', () async {
      final tokens = <ClientTokenSummary>[
        ClientTokenSummary(
          id: 'token-1',
          clientId: 'client-1',
          createdAt: DateTime(2026, 3, 12),
          isRevoked: false,
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: <ClientTokenRule>[],
        ),
      ];
      when(
        () => mockListClientTokens(),
      ).thenAnswer((_) async => Success(tokens));

      final success = await provider.loadTokens();

      expect(success, isTrue);
      expect(provider.tokens, hasLength(1));
      expect(provider.tokens.first.id, equals('token-1'));
      expect(provider.error, isEmpty);
      expect(provider.hasLoaded, isTrue);
    });

    test('should create token and refresh list', () async {
      when(
        () => mockCreateClientToken(any()),
      ).thenAnswer((_) async => const Success('new-token'));
      when(
        () => mockListClientTokens(),
      ).thenAnswer(
        (_) async => Success(<ClientTokenSummary>[
          ClientTokenSummary(
            id: 'token-1',
            clientId: 'client-1',
            createdAt: DateTime(2026, 3, 12),
            isRevoked: false,
            allTables: false,
            allViews: false,
            allPermissions: false,
            rules: <ClientTokenRule>[],
          ),
        ]),
      );

      final success = await provider.createToken(_buildRequest());

      expect(success, isTrue);
      expect(provider.lastCreatedToken, equals('new-token'));
      expect(provider.tokens, hasLength(1));
      expect(provider.error, isEmpty);
    });

    test('should expose failure message when create fails', () async {
      when(() => mockCreateClientToken(any())).thenAnswer(
        (_) async => Failure(domain.ValidationFailure('invalid request')),
      );

      final success = await provider.createToken(_buildRequest());

      expect(success, isFalse);
      expect(provider.lastCreatedToken, isNull);
      expect(provider.error, contains('invalid request'));
    });

    test('should revoke token and refresh list', () async {
      when(
        () => mockRevokeClientToken('token-1'),
      ).thenAnswer((_) async => const Success(unit));
      when(
        () => mockListClientTokens(),
      ).thenAnswer((_) async => const Success(<ClientTokenSummary>[]));

      final success = await provider.revokeToken('token-1');

      expect(success, isTrue);
      expect(provider.tokens, isEmpty);
      expect(provider.error, isEmpty);
    });
  });
}

ClientTokenCreateRequest _buildRequest() {
  return const ClientTokenCreateRequest(
    clientId: 'client-1',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: [
      ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'dbo.clientes',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      ),
    ],
  );
}

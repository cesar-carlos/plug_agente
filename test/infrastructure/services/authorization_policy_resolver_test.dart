import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockClientTokenLocalDataSource extends Mock
    implements ClientTokenLocalDataSource {}

class MockJwtJwksVerifier extends Mock implements JwtJwksVerifier {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  group('AuthorizationPolicyResolver', () {
    late AuthorizationPolicyResolver resolver;
    late MockFeatureFlags mockFeatureFlags;
    late MockClientTokenLocalDataSource mockLocalDataSource;
    late MockJwtJwksVerifier mockJwksVerifier;
    late MockTokenAuditStore mockTokenAuditStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockFeatureFlags = MockFeatureFlags();
      mockLocalDataSource = MockClientTokenLocalDataSource();
      mockJwksVerifier = MockJwtJwksVerifier();
      mockTokenAuditStore = MockTokenAuditStore();
      when(() => mockFeatureFlags.enableSocketJwksValidation).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketRevokedTokenInSession,
      ).thenReturn(false);
      when(
        () => mockTokenAuditStore.record(any()),
      ).thenAnswer((_) async {});
      resolver = AuthorizationPolicyResolver(mockFeatureFlags);
    });

    test('should resolve policy from JWT payload', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'client-acme',
          'all_tables': true,
          'all_views': false,
          'all_permissions': true,
          'rules': const <Map<String, dynamic>>[],
        },
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isSuccess(), isTrue);
      result.fold((policy) {
        expect(policy.clientId, equals('client-acme'));
        expect(policy.allPermissions, isTrue);
      }, (_) => fail('Expected success'));
    });

    test('should return failure for malformed token', () async {
      final result = await resolver.resolvePolicy('invalid-token');

      expect(result.isError(), isTrue);
    });

    test('should return failure for revoked token', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'client-acme',
          'all_tables': false,
          'all_views': false,
          'all_permissions': false,
          'rules': const <Map<String, dynamic>>[],
        },
        'revoked': true,
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isError(), isTrue);
    });

    test('should reject token in revoked store when flag on', () async {
      when(
        () => mockFeatureFlags.enableSocketRevokedTokenInSession,
      ).thenReturn(true);
      final store = InMemoryRevokedTokenStore();
      store.add('revoked-token-xyz');
      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        revokedTokenStore: store,
      );

      final result = await resolver.resolvePolicy('revoked-token-xyz');

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (f) {
          final failure = f as domain.Failure;
          expect(failure.context['reason'], equals('token_revoked'));
        },
      );
    });

    test(
      'should add to revoked store when token revoked and flag on',
      () async {
        when(
          () => mockFeatureFlags.enableSocketRevokedTokenInSession,
        ).thenReturn(true);
        final store = InMemoryRevokedTokenStore();
        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          revokedTokenStore: store,
        );
        final token = _buildToken(<String, dynamic>{
          'policy': <String, dynamic>{
            'client_id': 'client-acme',
            'all_tables': false,
            'all_views': false,
            'all_permissions': false,
            'rules': const <Map<String, dynamic>>[],
          },
          'revoked': true,
        });

        final firstResult = await resolver.resolvePolicy(token);
        expect(firstResult.isError(), isTrue);

        final secondResult = await resolver.resolvePolicy(token);
        expect(secondResult.isError(), isTrue);
        expect(store.isRevoked(token), isTrue);
      },
    );

    test(
      'should resolve policy from local database when datasource provided',
      () async {
        const tokenId = 'token-123';
        const opaqueToken = 'abc123def456';
        const tokenHash = 'hash-of-abc123def456';

        final summary = ClientTokenSummary(
          id: tokenId,
          clientId: 'local-client',
          createdAt: DateTime.now().toUtc(),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: true,
          rules: const <ClientTokenRule>[
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.users',
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

        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => summary);

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isSuccess(), isTrue);
        result.fold((policy) {
          expect(policy.clientId, equals('local-client'));
          expect(policy.allPermissions, isTrue);
        }, (_) => fail('Expected success'));
        verify(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).called(1);
        verify(() => mockLocalDataSource.getTokenByHash(tokenHash)).called(1);
      },
    );

    test(
      'should return token_not_found when token is absent in local database',
      () async {
        const opaqueToken = 'missing-token-xyz';
        const tokenHash = 'hash-of-missing-token';

        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => null);

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final authFailure = failure as domain.Failure;
            expect(authFailure.context['reason'], equals('token_not_found'));
          },
        );
        verify(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).called(1);
        verify(() => mockLocalDataSource.getTokenByHash(tokenHash)).called(1);
      },
    );

    test(
      'should fallback to JWKS when local token is not found and JWKS is enabled',
      () async {
        const opaqueToken = 'missing-local-token-fallback';
        const tokenHash = 'hash-of-missing-token-fallback';
        when(
          () => mockFeatureFlags.enableSocketJwksValidation,
        ).thenReturn(true);
        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => null);
        when(
          () => mockJwksVerifier.verify(opaqueToken),
        ).thenAnswer(
          (_) async => const Success(<String, dynamic>{
            'policy': <String, dynamic>{
              'client_id': 'jwks-client',
              'all_tables': true,
              'all_views': false,
              'all_permissions': true,
              'rules': <Map<String, dynamic>>[],
            },
          }),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
          jwksVerifier: mockJwksVerifier,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (policy) => expect(policy.clientId, equals('jwks-client')),
          (_) => fail('Expected success'),
        );
        verify(() => mockJwksVerifier.verify(opaqueToken)).called(1);
      },
    );

    test(
      'should record authorization denied audit event on token_not_found',
      () async {
        const opaqueToken = 'missing-audit-token';
        const tokenHash = 'hash-of-missing-audit-token';
        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => null);

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
          tokenAuditStore: mockTokenAuditStore,
        );

        await resolver.resolvePolicy(opaqueToken);

        final captured = verify(
          () => mockTokenAuditStore.record(captureAny()),
        ).captured;
        expect(captured, isNotEmpty);
        final event = captured.first as TokenAuditEvent;
        expect(
          event.eventType,
          equals(TokenAuditEventType.authorizationDenied),
        );
        expect(event.metadata['reason'], equals('token_not_found'));
      },
    );

    test(
      'should return token_revoked when token is revoked in local database',
      () async {
        const tokenId = 'revoked-token';
        const opaqueToken = 'revoked-abc123';
        const tokenHash = 'hash-of-revoked-abc123';

        final summary = ClientTokenSummary(
          id: tokenId,
          clientId: 'client-acme',
          createdAt: DateTime.now().toUtc(),
          isRevoked: true,
          allTables: true,
          allViews: false,
          allPermissions: true,
          rules: const <ClientTokenRule>[],
        );

        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => summary);

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final authFailure = failure as domain.Failure;
            expect(authFailure.context['reason'], equals('token_revoked'));
          },
        );
        verify(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).called(1);
        verify(() => mockLocalDataSource.getTokenByHash(tokenHash)).called(1);
      },
    );
  });
}

String _buildToken(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$encodedPayload.signature';
}

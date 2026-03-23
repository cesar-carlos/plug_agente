import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:result_dart/result_dart.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockClientTokenLocalDataSource extends Mock
    implements ClientTokenLocalDataSource {}

class MockJwtJwksVerifier extends Mock implements JwtJwksVerifier {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

class MockClientTokenPolicyCache extends Mock
    implements IClientTokenPolicyCache {}

class MockAuthorizationCacheMetrics extends Mock
    implements IAuthorizationCacheMetrics {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026),
      ),
    );
    registerFallbackValue(
      const ClientTokenPolicy(
        clientId: 'fallback',
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: [],
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

    test(
      'should record audit when token is missing after normalization',
      () async {
        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          tokenAuditStore: mockTokenAuditStore,
        );

        await resolver.resolvePolicy('   ');

        final captured = verify(
          () => mockTokenAuditStore.record(captureAny()),
        ).captured;
        expect(captured, isNotEmpty);
        final event = captured.first as TokenAuditEvent;
        expect(
          event.eventType,
          equals(TokenAuditEventType.authorizationDenied),
        );
      },
    );

    test('should return cached policy without hitting local store', () async {
      final policyCache = MockClientTokenPolicyCache();
      final metrics = MockAuthorizationCacheMetrics();
      const token = 'cached-opaque';
      final hash = hashClientCredentialToken(token);
      const policy = ClientTokenPolicy(
        clientId: 'cached-client',
        allTables: true,
        allViews: false,
        allPermissions: false,
        rules: [],
      );
      when(() => policyCache.get(hash)).thenReturn(policy);
      when(
        () => metrics.recordPolicyCacheLookup(hit: any(named: 'hit')),
      ).thenReturn(null);

      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        localDataSource: mockLocalDataSource,
        policyCache: policyCache,
        cacheMetrics: metrics,
      );

      final result = await resolver.resolvePolicy(token);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull()?.clientId, equals('cached-client'));
      verify(() => policyCache.get(hash)).called(1);
      verifyNever(() => mockLocalDataSource.hashTokenForLookup(any()));
      verify(
        () => metrics.recordPolicyCacheLookup(hit: true),
      ).called(1);
    });

    test('should record policy cache miss before local lookup', () async {
      final policyCache = MockClientTokenPolicyCache();
      final metrics = MockAuthorizationCacheMetrics();
      const opaqueToken = 'miss-then-local';
      const tokenHash = 'h1';
      when(() => policyCache.get(any())).thenReturn(null);
      when(
        () => metrics.recordPolicyCacheLookup(hit: any(named: 'hit')),
      ).thenReturn(null);
      when(
        () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
      ).thenReturn(tokenHash);
      when(
        () => mockLocalDataSource.getTokenByHash(tokenHash),
      ).thenAnswer(
        (_) async => ClientTokenSummary(
          id: 'id1',
          clientId: 'c1',
          createdAt: DateTime.now().toUtc(),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: false,
          rules: const [],
        ),
      );

      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        localDataSource: mockLocalDataSource,
        policyCache: policyCache,
        cacheMetrics: metrics,
      );

      await resolver.resolvePolicy(opaqueToken);

      verify(() => metrics.recordPolicyCacheLookup(hit: false)).called(1);
      final putCaptured = verify(
        () => policyCache.put(
          hashClientCredentialToken(opaqueToken),
          captureAny<ClientTokenPolicy>(),
        ),
      ).captured;
      expect(putCaptured, hasLength(1));
      final stored = putCaptured.single as ClientTokenPolicy;
      expect(stored.clientId, equals('c1'));
      expect(stored.allTables, isTrue);
      expect(stored.allViews, isFalse);
      expect(stored.allPermissions, isFalse);
      expect(stored.rules, isEmpty);
    });

    test(
      'should fail decode-only path when token has no payload segment',
      () async {
        final result = await resolver.resolvePolicy('only-one-part');

        expect(result.isError(), isTrue);
      },
    );

    test('should fail when JWT payload is not valid base64', () async {
      final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
      final result = await resolver.resolvePolicy('$header.!!!.sig');

      expect(result.isError(), isTrue);
    });

    test(
      'should fail decode-only when payload JSON is not a policy object',
      () async {
        final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
        final payload = base64Url.encode(utf8.encode('[1]'));
        final token = '$header.$payload.sig';

        final result = await resolver.resolvePolicy(token);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.context['reason'], equals('invalid_policy'));
          },
        );
      },
    );

    test('should fail when policy client_id is blank', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': '   ',
          'all_tables': true,
          'all_views': false,
          'all_permissions': false,
          'rules': <Map<String, dynamic>>[],
        },
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          final f = failure as domain.Failure;
          expect(f.context['reason'], equals('invalid_policy'));
        },
      );
    });

    test('should fail when policy omits client_id', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'all_tables': true,
          'all_views': false,
          'all_permissions': false,
          'rules': <Map<String, dynamic>>[],
        },
      });

      final result = await resolver.resolvePolicy(token);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          final f = failure as domain.Failure;
          expect(f.context['reason'], equals('invalid_policy'));
        },
      );
    });

    test(
      'should return JWKS verification failure and skip audit for non-domain failure',
      () async {
        when(
          () => mockFeatureFlags.enableSocketJwksValidation,
        ).thenReturn(true);
        when(() => mockJwksVerifier.verify('jwt-opaque')).thenAnswer(
          (_) async => Failure(Exception('jwks offline')),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          jwksVerifier: mockJwksVerifier,
        );

        final result = await resolver.resolvePolicy('jwt-opaque');

        expect(result.isError(), isTrue);
        verifyNever(() => mockTokenAuditStore.record(any()));
      },
    );

    test(
      'should audit authorization denied when JWKS returns domain failure',
      () async {
        when(
          () => mockFeatureFlags.enableSocketJwksValidation,
        ).thenReturn(true);
        when(() => mockJwksVerifier.verify('jwt-bad-policy')).thenAnswer(
          (_) async => const Success(<String, dynamic>{
            'policy': <String, dynamic>{
              'client_id': '',
              'rules': <Map<String, dynamic>>[],
            },
          }),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          jwksVerifier: mockJwksVerifier,
          tokenAuditStore: mockTokenAuditStore,
        );

        await resolver.resolvePolicy('jwt-bad-policy');

        verify(() => mockTokenAuditStore.record(any())).called(1);
      },
    );

    test('should cache policy after successful JWKS verification', () async {
      when(
        () => mockFeatureFlags.enableSocketJwksValidation,
      ).thenReturn(true);
      const token = 'jwks-cache-me';
      when(() => mockJwksVerifier.verify(token)).thenAnswer(
        (_) async => const Success(<String, dynamic>{
          'policy': <String, dynamic>{
            'client_id': 'jwks-cached',
            'all_tables': true,
            'all_views': false,
            'all_permissions': false,
            'rules': <Map<String, dynamic>>[],
          },
        }),
      );
      final policyCache = MockClientTokenPolicyCache();
      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        jwksVerifier: mockJwksVerifier,
        policyCache: policyCache,
      );

      await resolver.resolvePolicy(token);

      final captured = verify(
        () => policyCache.put(
          hashClientCredentialToken(token),
          captureAny<ClientTokenPolicy>(),
        ),
      ).captured;
      expect(captured, hasLength(1));
      expect(
        (captured.single as ClientTokenPolicy).clientId,
        equals('jwks-cached'),
      );
    });

    test('should cache policy after successful decode-only JWT', () async {
      final token = _buildToken(<String, dynamic>{
        'policy': <String, dynamic>{
          'client_id': 'decode-cached',
          'all_tables': false,
          'all_views': true,
          'all_permissions': false,
          'rules': <Map<String, dynamic>>[],
        },
      });
      final policyCache = MockClientTokenPolicyCache();
      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        policyCache: policyCache,
      );

      await resolver.resolvePolicy(token);

      final captured = verify(
        () => policyCache.put(
          hashClientCredentialToken(token),
          captureAny<ClientTokenPolicy>(),
        ),
      ).captured;
      expect(captured, hasLength(1));
      expect(
        (captured.single as ClientTokenPolicy).clientId,
        equals('decode-cached'),
      );
    });

    test(
      'should add revoked token to session store and emit revokedInSession audit',
      () async {
        when(
          () => mockFeatureFlags.enableSocketRevokedTokenInSession,
        ).thenReturn(true);
        const opaqueToken = 'revoke-local-1';
        const tokenHash = 'hash-revoke-local-1';
        final summary = ClientTokenSummary(
          id: 'tid',
          clientId: 'c1',
          createdAt: DateTime.now().toUtc(),
          isRevoked: true,
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: const [],
        );
        when(
          () => mockLocalDataSource.hashTokenForLookup(opaqueToken),
        ).thenReturn(tokenHash);
        when(
          () => mockLocalDataSource.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => summary);

        final store = InMemoryRevokedTokenStore();
        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          localDataSource: mockLocalDataSource,
          revokedTokenStore: store,
          tokenAuditStore: mockTokenAuditStore,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isError(), isTrue);
        expect(store.isRevoked(opaqueToken), isTrue);
        final captured = verify(
          () => mockTokenAuditStore.record(captureAny()),
        ).captured;
        final revokedEvent = captured.cast<TokenAuditEvent>().firstWhere(
          (TokenAuditEvent e) =>
              e.eventType == TokenAuditEventType.revokedInSession,
        );
        expect(revokedEvent.metadata['reason'], equals('token_revoked'));
      },
    );

    test('should swallow audit store errors when recording denied', () async {
      when(() => mockTokenAuditStore.record(any())).thenAnswer((_) async {
        throw Exception('audit sink down');
      });

      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        tokenAuditStore: mockTokenAuditStore,
      );

      final result = await resolver.resolvePolicy('');

      expect(result.isError(), isTrue);
    });
  });
}

String _buildToken(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$encodedPayload.signature';
}

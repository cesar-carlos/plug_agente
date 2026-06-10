import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:result_dart/result_dart.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockClientTokenRepository extends Mock implements IClientTokenRepository {}

class MockJwtJwksVerifier extends Mock implements JwtJwksVerifier {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026),
      ),
    );
  });

  group('AuthorizationPolicyResolver', () {
    late AuthorizationPolicyResolver resolver;
    late MockFeatureFlags mockFeatureFlags;
    late MockClientTokenRepository mockClientTokenRepository;
    late MockJwtJwksVerifier mockJwksVerifier;
    late MockTokenAuditStore mockTokenAuditStore;

    setUp(() async {
      mockFeatureFlags = MockFeatureFlags();
      mockClientTokenRepository = MockClientTokenRepository();
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

    test(
      'should reject unsigned JWT decode when JWKS disabled and token not in local store',
      () async {
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

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final authFailure = failure as domain.Failure;
            expect(
              authFailure.context['reason'],
              equals(AuthorizationContextConstants.invalidTokenSignatureReason),
            );
          },
        );
      },
    );

    test('should return failure for malformed token', () async {
      final result = await resolver.resolvePolicy('invalid-token');

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          final authFailure = failure as domain.Failure;
          expect(
            authFailure.context['reason'],
            equals(AuthorizationContextConstants.invalidTokenSignatureReason),
          );
        },
      );
    });

    test('should return failure for revoked token via JWKS payload', () async {
      when(() => mockFeatureFlags.enableSocketJwksValidation).thenReturn(true);
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
      when(() => mockJwksVerifier.verify(token)).thenAnswer(
        (_) async => const Success(<String, dynamic>{
          'policy': <String, dynamic>{
            'client_id': 'client-acme',
            'all_tables': false,
            'all_views': false,
            'all_permissions': false,
            'rules': <Map<String, dynamic>>[],
          },
          'revoked': true,
        }),
      );
      resolver = AuthorizationPolicyResolver(
        mockFeatureFlags,
        jwksVerifier: mockJwksVerifier,
      );

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
          expect(failure.context['reason'], equals(AuthorizationContextConstants.tokenRevokedReason));
        },
      );
    });

    test(
      'should add to revoked store when token revoked and flag on',
      () async {
        when(
          () => mockFeatureFlags.enableSocketRevokedTokenInSession,
        ).thenReturn(true);
        when(() => mockFeatureFlags.enableSocketJwksValidation).thenReturn(true);
        final store = InMemoryRevokedTokenStore();
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
        when(() => mockJwksVerifier.verify(token)).thenAnswer(
          (_) async => const Success(<String, dynamic>{
            'policy': <String, dynamic>{
              'client_id': 'client-acme',
              'all_tables': false,
              'all_views': false,
              'all_permissions': false,
              'rules': <Map<String, dynamic>>[],
            },
            'revoked': true,
          }),
        );
        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          jwksVerifier: mockJwksVerifier,
          revokedTokenStore: store,
        );

        final firstResult = await resolver.resolvePolicy(token);
        expect(firstResult.isError(), isTrue);

        final secondResult = await resolver.resolvePolicy(token);
        expect(secondResult.isError(), isTrue);
        expect(store.isRevoked(token), isTrue);
      },
    );

    test(
      'should resolve policy from local repository when configured',
      () async {
        const tokenId = 'token-123';
        const opaqueToken = 'abc123def456';
        final tokenHash = hashClientCredentialToken(opaqueToken);

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
          () => mockClientTokenRepository.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => Success(summary));

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          clientTokenRepository: mockClientTokenRepository,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isSuccess(), isTrue);
        result.fold((policy) {
          expect(policy.clientId, equals('local-client'));
          expect(policy.allPermissions, isTrue);
        }, (_) => fail('Expected success'));
        verify(() => mockClientTokenRepository.getTokenByHash(tokenHash)).called(1);
      },
    );

    test(
      'should return token_not_found when token is absent in local repository',
      () async {
        const opaqueToken = 'missing-token-xyz';
        final tokenHash = hashClientCredentialToken(opaqueToken);

        when(() => mockClientTokenRepository.getTokenByHash(tokenHash)).thenAnswer(
          (_) async => Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: const {'operation': 'get_local_client_token_by_hash'},
            ),
          ),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          clientTokenRepository: mockClientTokenRepository,
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
        verify(() => mockClientTokenRepository.getTokenByHash(tokenHash)).called(1);
      },
    );

    test(
      'should map repository DB errors to authentication failure without decode fallback',
      () async {
        const opaqueToken = 'db-error-token';
        final tokenHash = hashClientCredentialToken(opaqueToken);

        when(() => mockClientTokenRepository.getTokenByHash(tokenHash)).thenAnswer(
          (_) async => Failure(
            domain.ServerFailure.withContext(
              message: 'Failed to load local client token',
              context: const {'operation': 'get_local_client_token_by_hash'},
            ),
          ),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          clientTokenRepository: mockClientTokenRepository,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final authFailure = failure as domain.Failure;
            expect(
              authFailure.context['reason'],
              equals(AuthorizationContextConstants.unauthorizedReason),
            );
            expect(authFailure.context['authentication'], isTrue);
          },
        );
      },
    );

    test(
      'should fallback to JWKS when local token is not found and JWKS is enabled',
      () async {
        const opaqueToken = 'missing-local-token-fallback';
        final tokenHash = hashClientCredentialToken(opaqueToken);
        when(
          () => mockFeatureFlags.enableSocketJwksValidation,
        ).thenReturn(true);
        when(() => mockClientTokenRepository.getTokenByHash(tokenHash)).thenAnswer(
          (_) async => Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: const {'operation': 'get_local_client_token_by_hash'},
            ),
          ),
        );
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
          clientTokenRepository: mockClientTokenRepository,
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
        final tokenHash = hashClientCredentialToken(opaqueToken);
        when(() => mockClientTokenRepository.getTokenByHash(tokenHash)).thenAnswer(
          (_) async => Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: const {'operation': 'get_local_client_token_by_hash'},
            ),
          ),
        );

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          clientTokenRepository: mockClientTokenRepository,
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
      'should return token_revoked when token is revoked in local repository',
      () async {
        const tokenId = 'revoked-token';
        const opaqueToken = 'revoked-abc123';
        final tokenHash = hashClientCredentialToken(opaqueToken);

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
          () => mockClientTokenRepository.getTokenByHash(tokenHash),
        ).thenAnswer((_) async => Success(summary));

        resolver = AuthorizationPolicyResolver(
          mockFeatureFlags,
          clientTokenRepository: mockClientTokenRepository,
        );

        final result = await resolver.resolvePolicy(opaqueToken);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final authFailure = failure as domain.Failure;
            expect(authFailure.context['reason'], equals(AuthorizationContextConstants.tokenRevokedReason));
          },
        );
        verify(() => mockClientTokenRepository.getTokenByHash(tokenHash)).called(1);
      },
    );
  });
}

String _buildToken(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final encodedPayload = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$encodedPayload.signature';
}

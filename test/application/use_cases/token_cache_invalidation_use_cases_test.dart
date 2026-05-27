import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

class MockClientTokenRepository extends Mock implements IClientTokenRepository {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

class MockAuthorizationDecisionCache extends Mock implements IAuthorizationDecisionCache {}

class MockClientTokenPolicyCache extends Mock implements IClientTokenPolicyCache {}

void main() {
  setUpAll(() {
    registerFallbackValue(_request());
    registerFallbackValue(
      TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026),
      ),
    );
  });

  group('Token cache invalidation use cases', () {
    late MockClientTokenRepository repository;
    late MockTokenAuditStore auditStore;
    late MockAuthorizationDecisionCache decisionCache;
    late MockClientTokenPolicyCache policyCache;

    setUp(() {
      repository = MockClientTokenRepository();
      auditStore = MockTokenAuditStore();
      decisionCache = MockAuthorizationDecisionCache();
      policyCache = MockClientTokenPolicyCache();
      when(() => auditStore.record(any())).thenAnswer((_) async {});
      when(() => decisionCache.invalidateAll()).thenAnswer((_) {});
      when(
        () => decisionCache.invalidateForCredentialHash(any()),
      ).thenAnswer((_) {});
      when(() => policyCache.invalidate(any())).thenAnswer((_) {});
      when(() => policyCache.invalidateAll()).thenAnswer((_) {});
    });

    test(
      'revoke should invalidate caches for credential hash when secret known',
      () async {
        when(
          () => repository.getTokenSecret('token-1'),
        ).thenAnswer(
          (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'secret-a')),
        );
        when(
          () => repository.revokeToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = RevokeClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verifyNever(() => decisionCache.invalidateAll());
        verifyNever(() => policyCache.invalidateAll());
        verify(
          () => decisionCache.invalidateForCredentialHash(
            hashClientCredentialToken('secret-a'),
          ),
        ).called(1);
        verify(
          () => policyCache.invalidate(hashClientCredentialToken('secret-a')),
        ).called(1);
      },
    );

    test(
      'revoke should flush all caches when token secret unavailable',
      () async {
        when(
          () => repository.getTokenSecret('token-1'),
        ).thenAnswer(
          (_) async => const Success(ClientTokenSecretLookup(tokenValue: null)),
        );
        when(
          () => repository.revokeToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = RevokeClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verify(() => decisionCache.invalidateAll()).called(1);
        verify(() => policyCache.invalidateAll()).called(1);
        verifyNever(() => decisionCache.invalidateForCredentialHash(any()));
      },
    );

    test(
      'delete should invalidate caches for credential hash when secret known',
      () async {
        when(
          () => repository.getTokenSecret('token-1'),
        ).thenAnswer(
          (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'secret-b')),
        );
        when(
          () => repository.deleteToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = DeleteClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verifyNever(() => decisionCache.invalidateAll());
        verify(
          () => decisionCache.invalidateForCredentialHash(
            hashClientCredentialToken('secret-b'),
          ),
        ).called(1);
        verify(
          () => policyCache.invalidate(hashClientCredentialToken('secret-b')),
        ).called(1);
      },
    );

    test('update should invalidate old and new credential hashes when token rotates', () async {
      when(
        () => repository.getTokenSecret('token-1'),
      ).thenAnswer(
        (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'old-secret')),
      );
      when(
        () => repository.updateToken(
          'token-1',
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ClientTokenUpdateResult(
            outcome: ClientTokenUpdateOutcome.rotated,
            tokenValue: 'new-secret',
            version: 2,
            updatedAt: DateTime.utc(2026, 3, 17),
          ),
        ),
      );

      final useCase = UpdateClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
        policyCache: policyCache,
      );

      final result = await useCase.call(
        'token-1',
        _request(),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      verifyNever(() => decisionCache.invalidateAll());
      verify(
        () => decisionCache.invalidateForCredentialHash(
          hashClientCredentialToken('old-secret'),
        ),
      ).called(1);
      verify(
        () => decisionCache.invalidateForCredentialHash(
          hashClientCredentialToken('new-secret'),
        ),
      ).called(1);
      verify(
        () => policyCache.invalidate(hashClientCredentialToken('old-secret')),
      ).called(1);
      verify(
        () => policyCache.invalidate(hashClientCredentialToken('new-secret')),
      ).called(1);
      verify(
        () => auditStore.record(
          any(that: isA<TokenAuditEvent>().having((e) => e.eventType, 'eventType', TokenAuditEventType.rotate)),
        ),
      ).called(1);
    });

    test('update should record metadataUpdate audit and skip cache invalidation when only metadata changes', () async {
      when(
        () => repository.getTokenSecret('token-1'),
      ).thenAnswer(
        (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'unchanged-secret')),
      );
      when(
        () => repository.updateToken(
          'token-1',
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ClientTokenUpdateResult(
            outcome: ClientTokenUpdateOutcome.metadataOnly,
            version: 2,
            updatedAt: DateTime.utc(2026, 3, 17),
          ),
        ),
      );

      final useCase = UpdateClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
        policyCache: policyCache,
      );

      final result = await useCase.call(
        'token-1',
        _request(),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      verifyNever(() => decisionCache.invalidateAll());
      verifyNever(() => policyCache.invalidateAll());
      verifyNever(() => decisionCache.invalidateForCredentialHash(any()));
      verifyNever(() => policyCache.invalidate(any()));
      verify(
        () => auditStore.record(
          any(
            that: isA<TokenAuditEvent>().having(
              (e) => e.eventType,
              'eventType',
              TokenAuditEventType.metadataUpdate,
            ),
          ),
        ),
      ).called(1);
    });

    test('update should skip caches and audit when nothing changed', () async {
      when(
        () => repository.getTokenSecret('token-1'),
      ).thenAnswer(
        (_) async => const Success(ClientTokenSecretLookup(tokenValue: 'unchanged-secret')),
      );
      when(
        () => repository.updateToken(
          'token-1',
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ClientTokenUpdateResult(
            outcome: ClientTokenUpdateOutcome.unchanged,
            version: 1,
            updatedAt: DateTime.utc(2026, 3, 17),
          ),
        ),
      );

      final useCase = UpdateClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
        policyCache: policyCache,
      );

      final result = await useCase.call(
        'token-1',
        _request(),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      verifyNever(() => decisionCache.invalidateAll());
      verifyNever(() => policyCache.invalidateAll());
      verifyNever(() => decisionCache.invalidateForCredentialHash(any()));
      verifyNever(() => policyCache.invalidate(any()));
      verifyNever(() => auditStore.record(any()));
    });
  });
}

ClientTokenCreateRequest _request() {
  return const ClientTokenCreateRequest(
    clientId: 'client-1',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: [
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
}

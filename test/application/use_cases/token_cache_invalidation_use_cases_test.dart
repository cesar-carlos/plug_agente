import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class MockClientTokenRepository extends Mock implements IClientTokenRepository {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

void main() {
  const request = ClientTokenCreateRequest(clientId: 'client', allTables: true, allViews: false, rules: []);
  late MockClientTokenRepository repository;
  late MockTokenAuditStore audit;
  setUpAll(() {
    registerFallbackValue(request);
    registerFallbackValue(TokenAuditEvent(eventType: TokenAuditEventType.create, timestamp: DateTime.utc(2026)));
  });
  setUp(() {
    repository = MockClientTokenRepository();
    audit = MockTokenAuditStore();
    when(() => audit.record(any())).thenAnswer((_) async {});
  });

  group('Token mutation use cases', () {
    for (final action in ['revoke', 'delete']) {
      test('$action delegates mutation without reading secrets and audits after success', () async {
        when(() => repository.revokeToken('id')).thenAnswer((_) async => const Success(unit));
        when(() => repository.deleteToken('id')).thenAnswer((_) async => const Success(unit));
        final result = action == 'revoke'
            ? await RevokeClientToken(repository, auditStore: audit)('id')
            : await DeleteClientToken(repository, auditStore: audit)('id');
        expect(result.isSuccess(), isTrue);
        verifyNever(() => repository.getTokenSecret(any()));
        final event = verify(() => audit.record(captureAny())).captured.single as TokenAuditEvent;
        expect(event.eventType, action == 'revoke' ? TokenAuditEventType.revoke : TokenAuditEventType.delete);
      });
    }

    test('failed revocation preserves repository failure and does not audit success', () async {
      final failure = domain.DatabaseFailure('Token storage unavailable');
      when(() => repository.revokeToken('id')).thenAnswer((_) async => Failure(failure));
      final result = await RevokeClientToken(repository, auditStore: audit)('id');
      expect(result.exceptionOrNull(), same(failure));
      verifyNever(() => audit.record(any()));
      verifyNever(() => repository.getTokenSecret(any()));
    });

    for (final outcome in ClientTokenUpdateOutcome.values) {
      test('update delegates $outcome without reading secrets and records the corresponding audit', () async {
        final saved = ClientTokenUpdateResult(
          outcome: outcome,
          tokenValue: outcome == ClientTokenUpdateOutcome.rotated ? 'new-token' : null,
          version: 2,
          updatedAt: DateTime.utc(2026),
        );
        when(() => repository.updateToken('id', request, expectedVersion: 1)).thenAnswer((_) async => Success(saved));
        final result = await UpdateClientToken(repository, auditStore: audit)('id', request, expectedVersion: 1);
        expect(result.getOrThrow(), same(saved));
        verifyNever(() => repository.getTokenSecret(any()));
        if (outcome == ClientTokenUpdateOutcome.unchanged) {
          verifyNever(() => audit.record(any()));
        } else {
          final event = verify(() => audit.record(captureAny())).captured.single as TokenAuditEvent;
          expect(
            event.eventType,
            outcome == ClientTokenUpdateOutcome.rotated
                ? TokenAuditEventType.rotate
                : TokenAuditEventType.metadataUpdate,
          );
        }
      });
    }
  });
}

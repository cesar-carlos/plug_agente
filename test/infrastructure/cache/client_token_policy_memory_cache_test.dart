import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('ClientTokenPolicyMemoryCache', () {
    ClientTokenPolicy policy(String id) {
      return ClientTokenPolicy(
        clientId: id,
        allTables: true,
        allViews: true,
        allPermissions: true,
        rules: const [],
      );
    }

    test('TTL expires at its exact deadline even if the credential expires later', () {
      var now = DateTime.utc(2026, 10, 8);
      final deadline = now.add(const Duration(seconds: 30));
      final cache = ClientTokenPolicyMemoryCache(now: () => now);
      cache.put(
        'h',
        ClientTokenPolicy(
          clientId: 'c',
          allTables: true,
          allViews: true,
          allPermissions: true,
          rules: const [],
          credentialExpiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      now = deadline.subtract(const Duration(microseconds: 1));
      expect(cache.get('h'), isNotNull);
      now = deadline;
      expect(cache.get('h'), isNull);
    });

    test('expired pending policy never enters the cache', () async {
      var now = DateTime.utc(2026, 10, 8);
      final deadline = now.add(const Duration(seconds: 10));
      final cache = ClientTokenPolicyMemoryCache(now: () => now);
      final completion = Completer<Result<ClientTokenPolicy>>();
      final pending = cache.resolveSingleFlight('h', () => completion.future);
      now = deadline;
      completion.complete(
        Success(
          ClientTokenPolicy(
            clientId: 'c',
            allTables: true,
            allViews: true,
            allPermissions: true,
            rules: const [],
            credentialExpiresAt: deadline,
          ),
        ),
      );
      await pending;
      expect(cache.get('h'), isNull);
      expect(cache.hasPendingResolution('h'), isFalse);
    });

    test('limits backing lookups while allowing joins and preserving slots across invalidation', () async {
      final cache = ClientTokenPolicyMemoryCache(maxEntries: 2);
      final firstLoader = Completer<Result<ClientTokenPolicy>>();
      final secondLoader = Completer<Result<ClientTokenPolicy>>();
      final first = cache.resolveSingleFlight('a', () => firstLoader.future);
      final second = cache.resolveSingleFlight('b', () => secondLoader.future);
      final joined = cache.resolveSingleFlight('a', () async => throw StateError('must join existing lookup'));
      expect(joined, same(first));
      cache.invalidate('a');
      final blocked = await cache.resolveSingleFlight(
        'c',
        () async => throw StateError('must not start over capacity'),
      );
      final failure = blocked.result.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.policyResolutionBusyReason);
      expect(failure.isTransient, isTrue);
      expect(blocked.isCurrent, isTrue);
      expect(cache.hasPendingResolution('c'), isFalse);
      firstLoader.complete(Success(policy('a')));
      secondLoader.complete(Success(policy('b')));
      expect((await first).isCurrent, isFalse);
      expect((await second).isCurrent, isTrue);
      expect((await cache.resolveSingleFlight('c', () async => Success(policy('c')))).result.isSuccess(), isTrue);
    });

    test('times out shared callers, rejects overload and discards late success before retry', () async {
      final cache = ClientTokenPolicyMemoryCache(
        maxPendingResolutions: 1,
        resolutionTimeout: const Duration(milliseconds: 20),
      );
      final loader = Completer<Result<ClientTokenPolicy>>();
      final first = cache.resolveSingleFlight('a', () => loader.future);
      final joined = cache.resolveSingleFlight('a', () async => throw StateError('must not duplicate lookup'));
      final timeout = await first;
      expect((await joined).result, same(timeout.result));
      final failure = timeout.result.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.policyResolutionTimeoutReason);
      expect(failure.isTransient, isTrue);
      expect(timeout.isCurrent, isTrue);
      expect(cache.hasPendingResolution('a'), isFalse);
      cache.invalidateAll();
      final blocked = await cache.resolveSingleFlight(
        'a',
        () async => throw StateError('physical lookup still occupies capacity'),
      );
      expect(
        (blocked.result.exceptionOrNull()! as domain.ConfigurationFailure).context['reason'],
        AuthorizationContextConstants.policyResolutionBusyReason,
      );
      loader.complete(Success(policy('obsolete')));
      await Future<void>.delayed(Duration.zero);
      expect(cache.get('a'), isNull);
      final retry = await cache.resolveSingleFlight('a', () async => Success(policy('current')));
      expect(retry.result.getOrThrow().clientId, 'current');
      expect(cache.get('a')?.clientId, 'current');
    });

    test('maps an unexpected loader exception and releases capacity for the next request', () async {
      final cache = ClientTokenPolicyMemoryCache(maxPendingResolutions: 1);
      final failed = await cache.resolveSingleFlight('a', () => throw Exception('sensitive credential'));
      final failure = failed.result.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.policyResolutionFailedReason);
      expect(failure.isTransient, isTrue);
      expect(failure.toString(), isNot(contains('sensitive credential')));
      expect(
        (await cache.resolveSingleFlight('a', () async => Success(policy('recovered')))).result.isSuccess(),
        isTrue,
      );
    });

    test('get returns null for unknown hash', () {
      final cache = ClientTokenPolicyMemoryCache();
      expect(cache.get('unknown'), isNull);
    });

    test('put and get returns policy', () {
      final cache = ClientTokenPolicyMemoryCache();
      final p = policy('c1');
      cache.put('h1', p);
      expect(cache.get('h1')?.clientId, 'c1');
    });

    test('expires entries after ttl', () async {
      final cache = ClientTokenPolicyMemoryCache(
        ttl: const Duration(milliseconds: 40),
        maxEntries: 100,
      );
      cache.put('h1', policy('c1'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cache.get('h1'), isNull);
    });

    test('evicts oldest when over maxEntries', () {
      final cache = ClientTokenPolicyMemoryCache(
        ttl: const Duration(hours: 1),
        maxEntries: 2,
      );
      cache.put('a', policy('a'));
      cache.put('b', policy('b'));
      cache.put('c', policy('c'));

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNotNull);
      expect(cache.get('c'), isNotNull);
    });

    test('invalidate removes entry', () {
      final cache = ClientTokenPolicyMemoryCache();
      cache.put('h', policy('c'));
      cache.invalidate('h');
      expect(cache.get('h'), isNull);
    });

    test('invalidateAll clears cache', () {
      final cache = ClientTokenPolicyMemoryCache();
      cache.put('h', policy('c'));
      cache.invalidateAll();
      expect(cache.get('h'), isNull);
    });

    test('shares one pending lookup and does not cache a result invalidated mid-flight', () async {
      final cache = ClientTokenPolicyMemoryCache();
      final completer = Completer<Result<ClientTokenPolicy>>();
      var calls = 0;
      Future<Result<ClientTokenPolicy>> load() {
        calls++;
        return completer.future;
      }

      final first = cache.resolveSingleFlight('h', load);
      final second = cache.resolveSingleFlight('h', load);
      expect(cache.hasPendingResolution('h'), isTrue);
      expect(calls, 1);

      cache.invalidate('h');
      completer.complete(Success(policy('c1')));
      final firstResult = await first;
      final secondResult = await second;

      expect(firstResult.isCurrent, isFalse);
      expect(secondResult.isCurrent, isFalse);
      expect(cache.get('h'), isNull);
    });
  });
}

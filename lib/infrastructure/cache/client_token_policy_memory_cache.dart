import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:result_dart/result_dart.dart';

/// In-memory TTL cache for resolved [ClientTokenPolicy] by credential hash.
///
/// Cleared when client tokens are updated, revoked, or deleted (same time as
/// the authorization decision cache). Completed entries use [maxEntries] (LRU).
/// Backing lookups use [maxPendingResolutions], even after logical timeout or
/// invalidation, because their underlying I/O cannot always be cancelled.
class ClientTokenPolicyMemoryCache implements IClientTokenPolicyCache {
  ClientTokenPolicyMemoryCache({
    Duration ttl = const Duration(seconds: 30),
    this.maxEntries = 2048,
    int? maxPendingResolutions,
    this.resolutionTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : assert(maxEntries >= 0, 'Completed policy cache capacity cannot be negative'),
       assert(maxPendingResolutions == null || maxPendingResolutions > 0, 'Pending lookup capacity must be positive'),
       assert(resolutionTimeout > Duration.zero, 'Policy resolution timeout must be positive'),
       maxPendingResolutions =
           maxPendingResolutions ??
           (maxEntries > 0 && maxEntries < _defaultMaxPendingResolutions ? maxEntries : _defaultMaxPendingResolutions),
       _ttl = ttl,
       _now = now ?? DateTime.now,
       _entries = LinkedHashMap<String, _PolicyCacheEntry>();

  static const _defaultMaxPendingResolutions = 128;

  final Duration _ttl;
  final DateTime Function() _now;
  final int maxEntries;
  final int maxPendingResolutions;
  final Duration resolutionTimeout;
  int _inFlightCount = 0;
  final LinkedHashMap<String, _PolicyCacheEntry> _entries;
  final Map<String, _PendingPolicyResolution> _pending = <String, _PendingPolicyResolution>{};

  @override
  ClientTokenPolicy? get(String credentialHash) {
    final entry = _entries.remove(credentialHash);
    if (entry == null) {
      return null;
    }
    if (!_now().isBefore(entry.expiresAt)) {
      return null;
    }
    _entries[credentialHash] = entry;
    return entry.policy;
  }

  @override
  void put(String credentialHash, ClientTokenPolicy policy) {
    _entries.remove(credentialHash);
    final now = _now();
    var expiresAt = now.add(_ttl);
    final credentialExpiry = policy.credentialExpiresAt;
    if (credentialExpiry != null && credentialExpiry.isBefore(expiresAt)) {
      expiresAt = credentialExpiry;
    }
    if (!now.isBefore(expiresAt)) return;
    _entries[credentialHash] = _PolicyCacheEntry(policy: policy, expiresAt: expiresAt);
    _evictExcess();
  }

  void _evictExcess() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void invalidate(String credentialHash) {
    _entries.remove(credentialHash);
    // Removing the entry makes an already-running lookup stale. The lookup is
    // intentionally not cancellable (SQLite/JWKS may already be in progress),
    // but it can no longer populate or authorize through this cache.
    _pending.remove(credentialHash);
  }

  @override
  void invalidateAll() {
    _entries.clear();
    _pending.clear();
  }

  @override
  bool hasPendingResolution(String credentialHash) => _pending.containsKey(credentialHash);

  @override
  Future<ClientTokenPolicyResolution> resolveSingleFlight(
    String credentialHash,
    Future<Result<ClientTokenPolicy>> Function() loader,
  ) {
    final active = _pending[credentialHash];
    if (active != null) {
      return active.future;
    }

    if (_inFlightCount >= maxPendingResolutions) {
      return Future.value(
        ClientTokenPolicyResolution(
          result: Failure(
            _resolutionFailure(
              reason: AuthorizationContextConstants.policyResolutionBusyReason,
              message: 'Token policy resolution is at capacity',
            ),
          ),
          isCurrent: true,
        ),
      );
    }

    _inFlightCount++;
    late final _PendingPolicyResolution pending;
    final future = _load(loader)
        .timeout(
          resolutionTimeout,
          onTimeout: () => Failure(
            _resolutionFailure(
              reason: AuthorizationContextConstants.policyResolutionTimeoutReason,
              message: 'Token policy resolution timed out',
            ),
          ),
        )
        .then((result) {
          final isCurrent = identical(_pending[credentialHash], pending);
          if (isCurrent && result.isSuccess()) {
            final policy = result.getOrNull();
            if (policy != null) {
              put(credentialHash, policy);
            }
          }
          return ClientTokenPolicyResolution(result: result, isCurrent: isCurrent);
        })
        .whenComplete(() {
          if (identical(_pending[credentialHash], pending)) {
            _pending.remove(credentialHash);
          }
        });
    pending = _PendingPolicyResolution(future);
    _pending[credentialHash] = pending;
    return future;
  }

  Future<Result<ClientTokenPolicy>> _load(Future<Result<ClientTokenPolicy>> Function() loader) async {
    try {
      return await loader();
    } on Exception catch (error) {
      return Failure(
        _resolutionFailure(
          reason: AuthorizationContextConstants.policyResolutionFailedReason,
          message: 'Token policy lookup failed',
          causeType: error.runtimeType.toString(),
        ),
      );
    } finally {
      // A logical timeout does not cancel SQLite/JOSE. Keep the physical slot
      // occupied until completion, including across cache invalidation.
      _inFlightCount--;
    }
  }

  domain.ConfigurationFailure _resolutionFailure({required String reason, required String message, String? causeType}) {
    return domain.ConfigurationFailure.withContext(
      message: message,
      context: {
        'authentication': true,
        'reason': reason,
        'retryable': true,
        'cause_type': ?causeType,
        'user_message': 'Consulta da politica do token indisponivel. Aguarde e tente novamente.',
      },
    );
  }
}

class _PolicyCacheEntry {
  _PolicyCacheEntry({
    required this.policy,
    required this.expiresAt,
  });

  final ClientTokenPolicy policy;
  final DateTime expiresAt;
}

class _PendingPolicyResolution {
  const _PendingPolicyResolution(this.future);

  final Future<ClientTokenPolicyResolution> future;
}

import 'dart:collection';

import 'package:plug_agente/domain/protocol/rpc_request.dart';

enum RpcRequestGuardResult {
  allow,
  rateLimited,
  replayDetected,
}

class RpcRequestGuard {
  RpcRequestGuard({
    DateTime Function()? nowProvider,
    Duration rateLimitWindow = const Duration(minutes: 1),
    int maxRequestsPerWindow = 120,
    Duration replayWindow = const Duration(minutes: 2),
  }) : _nowProvider = nowProvider ?? DateTime.now,
       _rateLimitWindow = rateLimitWindow,
       _maxRequestsPerWindow = maxRequestsPerWindow,
       _replayWindow = replayWindow;

  final DateTime Function() _nowProvider;
  final Duration _rateLimitWindow;
  final int _maxRequestsPerWindow;
  final Duration _replayWindow;
  final Queue<DateTime> _rpcRequestTimeline = Queue<DateTime>();
  final Map<String, DateTime> _recentRpcRequestIds = <String, DateTime>{};

  RpcRequestGuardResult evaluate(RpcRequest request) {
    final now = _nowProvider();
    _registerRequest(now);

    if (_isRateLimited(now)) {
      return RpcRequestGuardResult.rateLimited;
    }

    final requestId = request.id?.toString();
    if (requestId == null || requestId.trim().isEmpty) {
      return RpcRequestGuardResult.allow;
    }

    _cleanupReplayCache(now);
    if (_recentRpcRequestIds.containsKey(requestId)) {
      return RpcRequestGuardResult.replayDetected;
    }

    _recentRpcRequestIds[requestId] = now;
    return RpcRequestGuardResult.allow;
  }

  void _registerRequest(DateTime now) {
    _rpcRequestTimeline.add(now);
    _evictExpiredFromTimeline(now);
  }

  void _evictExpiredFromTimeline(DateTime now) {
    final cutoff = now.subtract(_rateLimitWindow);
    while (_rpcRequestTimeline.isNotEmpty && _rpcRequestTimeline.first.isBefore(cutoff)) {
      _rpcRequestTimeline.removeFirst();
    }
  }

  bool _isRateLimited(DateTime now) {
    _evictExpiredFromTimeline(now);
    return _rpcRequestTimeline.length > _maxRequestsPerWindow;
  }

  void _cleanupReplayCache(DateTime now) {
    final cutoff = now.subtract(_replayWindow);
    _recentRpcRequestIds.removeWhere((_, time) => time.isBefore(cutoff));
  }
}

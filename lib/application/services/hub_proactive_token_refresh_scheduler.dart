import 'dart:async';

import 'package:plug_agente/core/utils/jwt_payload_reader.dart';

/// Schedules hub access-token refresh shortly before JWT expiry.
class HubProactiveTokenRefreshScheduler {
  HubProactiveTokenRefreshScheduler({
    required Duration refreshBeforeExpiry,
    required String? Function() accessTokenProvider,
    required Future<void> Function() onRefreshDue,
    DateTime Function()? now,
  }) : _refreshBeforeExpiry = refreshBeforeExpiry,
       _accessTokenProvider = accessTokenProvider,
       _onRefreshDue = onRefreshDue,
       _now = now ?? DateTime.now;

  final Duration _refreshBeforeExpiry;
  final String? Function() _accessTokenProvider;
  final Future<void> Function() _onRefreshDue;
  final DateTime Function() _now;

  Timer? _timer;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  void reschedule() {
    cancel();
    final token = _accessTokenProvider()?.trim();
    if (token == null || token.isEmpty) {
      return;
    }

    final delay = JwtPayloadReader.delayUntilProactiveRefresh(
      accessToken: token,
      margin: _refreshBeforeExpiry,
      now: _now(),
    );
    if (delay == null) {
      return;
    }

    _timer = Timer(delay, () {
      unawaited(_fireRefresh());
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _refreshQueued = false;
  }

  Future<void> _fireRefresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    try {
      await _onRefreshDue();
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(_fireRefresh());
      }
    }
  }

  void dispose() {
    cancel();
  }
}

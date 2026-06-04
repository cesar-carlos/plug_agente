import 'dart:async';
import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:test/test.dart';

String _jwtWithExp(int expSeconds) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode('{"exp":$expSeconds}')).replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  test('should invoke refresh when token is inside proactive margin', () async {
    var refreshCalls = 0;
    final exp = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final token = _jwtWithExp(exp.millisecondsSinceEpoch ~/ 1000);

    final scheduler = HubProactiveTokenRefreshScheduler(
      refreshBeforeExpiry: const Duration(minutes: 10),
      accessTokenProvider: () => token,
      onRefreshDue: () async {
        refreshCalls++;
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.reschedule();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    check(refreshCalls).equals(1);
  });

  test('should queue refresh when a refresh is already in flight', () async {
    final exp = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final token = _jwtWithExp(exp.millisecondsSinceEpoch ~/ 1000);
    var refreshCalls = 0;
    final refreshStarted = Completer<void>();

    final scheduler = HubProactiveTokenRefreshScheduler(
      refreshBeforeExpiry: const Duration(minutes: 10),
      accessTokenProvider: () => token,
      onRefreshDue: () async {
        refreshCalls++;
        if (refreshCalls == 1) {
          refreshStarted.complete();
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.reschedule();
    await refreshStarted.future;
    scheduler.reschedule();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    check(refreshCalls).equals(2);
  });

  test('should not schedule refresh when access token is unavailable', () async {
    var refreshCalls = 0;
    final scheduler = HubProactiveTokenRefreshScheduler(
      refreshBeforeExpiry: const Duration(minutes: 10),
      accessTokenProvider: () => null,
      onRefreshDue: () async {
        refreshCalls++;
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.reschedule();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    check(refreshCalls).equals(0);
  });
}

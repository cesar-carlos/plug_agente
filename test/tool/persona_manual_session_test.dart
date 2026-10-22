import 'package:flutter_test/flutter_test.dart';
import '../../tool/homologation/persona_manual_session.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  test('automated companion retains its twelve minute lifetime', () {
    expect(fixtureSessionDeadline({}, const Duration(minutes: 12), now: now), now.add(const Duration(minutes: 12)));
  });
  test('manual companion fixes expiry without extending it on reread', () {
    final expiry = now.add(const Duration(hours: 1));
    final manifest = <String, Object?>{
      'manualTraining': {'format': 'persona-manual-training-v1', 'expiresAt': expiry.toIso8601String()},
    };
    expect(fixtureSessionDeadline(manifest, Duration.zero, now: now.add(const Duration(minutes: 10))), expiry);
  });
  test('invalid, expired and excessive manual lifetimes are refused', () {
    for (final raw in <Object?>[
      null,
      {'format': 'wrong', 'expiresAt': now.add(const Duration(hours: 1)).toIso8601String()},
      {'format': 'persona-manual-training-v1', 'expiresAt': now.toIso8601String()},
      {'format': 'persona-manual-training-v1', 'expiresAt': now.add(const Duration(hours: 3)).toIso8601String()},
      {'format': 'persona-manual-training-v1', 'expiresAt': 'invalid'},
    ]) {
      expect(() => fixtureSessionDeadline({'manualTraining': raw}, Duration.zero, now: now), throwsStateError);
    }
  });
}

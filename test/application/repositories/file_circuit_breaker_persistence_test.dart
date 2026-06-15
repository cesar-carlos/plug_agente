import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/repositories/file_circuit_breaker_persistence.dart';

void main() {
  test('persists circuit breaker state across instances', () async {
    final tempDir = await Directory.systemTemp.createTemp('file_cb_persistence_test');
    final persistence = FileCircuitBreakerPersistence(
      fileName: 'automatic_failure_cb.json',
      basePath: tempDir.path,
    );

    await persistence.persistFailure(
      failureCount: 3,
      cooldownUntil: DateTime.utc(2030),
    );

    final reloaded = FileCircuitBreakerPersistence(
      fileName: 'automatic_failure_cb.json',
      basePath: tempDir.path,
    );

    expect(reloaded.failureCount, equals(3));
    expect(reloaded.cooldownUntil?.toUtc(), equals(DateTime.utc(2030)));
  });
}

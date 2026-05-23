import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/actions/agent_actions_bundle_file_gateway.dart';

void main() {
  test('should read back written bundle text', () async {
    final dir = await Directory.systemTemp.createTemp('plug_agente_bundle_gateway_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on Object catch (_) {
        // Best-effort cleanup.
      }
    });

    const gateway = AgentActionsBundleFileGateway();
    final path = '${dir.path}${Platform.pathSeparator}bundle.json';
    const payload = '{"hello":"world"}';

    final write = await gateway.writeText(path, payload);
    expect(write.isSuccess(), isTrue);

    final read = await gateway.readText(path);
    expect(read.isSuccess(), isTrue);
    expect(read.getOrNull(), payload);
  });

  test('should return failure when reading missing file', () async {
    const gateway = AgentActionsBundleFileGateway();
    final dir = await Directory.systemTemp.createTemp('plug_agente_bundle_missing_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on Object catch (_) {
        // Best-effort cleanup.
      }
    });
    final path = '${dir.path}${Platform.pathSeparator}missing_bundle.json';
    final read = await gateway.readText(path);
    expect(read.isError(), isTrue);
    final failure = read.exceptionOrNull();
    expect(failure, isA<domain.ServerFailure>());
  });
}

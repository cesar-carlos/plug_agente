import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_materialized_reader.dart';
import 'package:test/test.dart';

void main() {
  test(
    'only accepts the resource-aware schema with a bounded CPU limit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'elevated_schema_test_',
      );
      try {
        final file = File(
          ElevatedContract.materializedFilePath(directory.path, 'run'),
        );
        await file.parent.create(recursive: true);
        final reader = ElevatedMaterializedReader(
          appDirectoryPath: directory.path,
        );
        Future<void> write(Object version, Object cpu) => file.writeAsString(
          jsonEncode({
            'version': version,
            'executionId': 'run',
            'nonce': 'nonce',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
            'actionType': 'commandLine',
            'launch': {
              'executable': 'cmd.exe',
              'arguments': [],
              'cpuLimitPercent': cpu,
            },
          }),
        );
        await write(2, 50);
        expect(reader.read('run')!.launch.cpuLimitPercent, 50);
        for (final version in [1, 2.5, 3, '2']) {
          await write(version, 50);
          expect(reader.read('run'), isNull);
        }
        await write(2, 101);
        expect(reader.read('run'), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

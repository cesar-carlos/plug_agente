import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/infrastructure/backup/restore_failure_diagnostics.dart';

void main() {
  test('writeFromFailure creates last_restore_error.txt', () async {
    final dir = await Directory.systemTemp.createTemp('plug_diag_');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });

    final storage = GlobalStorageContext(appDirectoryPath: dir.path);
    await RestoreFailureDiagnostics.writeFromFailure(
      storage: storage,
      failure: ValidationFailure.withContext(
        message: 'test message',
        context: {'k': 'v'},
      ),
    );

    final file = File(p.join(dir.path, AppConstants.lastRestoreErrorFileName));
    expect(file.existsSync(), isTrue);
    final text = await file.readAsString();
    expect(text, contains('test message'));
    expect(text, contains('code:'));
  });
}

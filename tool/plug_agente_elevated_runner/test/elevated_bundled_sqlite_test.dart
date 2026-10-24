import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente_elevated_runner/src/elevated_bundled_sqlite.dart';
import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:test/test.dart';

void main() {
  test('loads the dedicated sidecar only from the helper directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'helper_sqlite_loader_',
    );
    try {
      final library = File(
        p.join(directory.path, ElevatedContract.sqliteSidecarFileName),
      );
      await library.writeAsBytes([0]);
      String? loaded;
      loadPackagedSqlite(
        executablePath: p.join(
          directory.path,
          'plug_agente_elevated_runner.exe',
        ),
        loader: (path) {
          loaded = path;
          return DynamicLibrary.process();
        },
      );
      expect(loaded, library.absolute.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  test(
    'fails before library lookup if the dedicated sidecar is missing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'helper_missing_sqlite_',
      );
      try {
        var searched = false;
        expect(
          () => loadPackagedSqlite(
            executablePath: p.join(
              directory.path,
              'plug_agente_elevated_runner.exe',
            ),
            loader: (_) {
              searched = true;
              return DynamicLibrary.process();
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(searched, isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

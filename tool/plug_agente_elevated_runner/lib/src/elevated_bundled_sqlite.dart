import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';

/// The packaged helper uses its own pinned SQLite, beside the executable.
/// Load by absolute path first, so the native binding cannot search PATH/CWD.
void loadPackagedSqlite({
  String? executablePath,
  DynamicLibrary Function(String)? loader,
}) {
  final executable = executablePath ?? Platform.resolvedExecutable;
  if (!Platform.isWindows ||
      p.basename(executable).toLowerCase() != 'plug_agente_elevated_runner.exe')
    return;
  final sidecar = File(
    p.join(
      p.dirname(p.absolute(executable)),
      ElevatedContract.sqliteSidecarFileName,
    ),
  );
  if (!sidecar.existsSync()) {
    throw FileSystemException(
      'Elevated helper SQLite is missing. Reinstall the complete application bundle.',
      sidecar.path,
    );
  }
  (loader ?? DynamicLibrary.open)(sidecar.path);
}

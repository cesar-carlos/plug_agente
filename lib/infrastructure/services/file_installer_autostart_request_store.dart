import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/autostart_install_request_constants.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';

class FileInstallerAutostartRequestStore implements IInstallerAutostartRequestStore {
  FileInstallerAutostartRequestStore({
    required String directoryPath,
    String markerFileName = AutostartInstallRequestConstants.markerFileName,
  }) : _markerFile = File(p.join(directoryPath, markerFileName));

  final File _markerFile;

  @override
  Future<bool> hasPendingRequest() async {
    return _markerFile.existsSync();
  }

  @override
  Future<void> clearPendingRequest() async {
    if (_markerFile.existsSync()) {
      await _markerFile.delete();
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/silent_install_failure.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_download.dart';

void main() {
  group('SilentUpdateInstallerDownload', () {
    test('isResumableDownloadError only accepts network failures', () {
      expect(
        SilentUpdateInstallerDownload.isResumableDownloadError(
          domain.NetworkFailure.withContext(message: 'timeout'),
        ),
        isTrue,
      );
      expect(
        SilentUpdateInstallerDownload.isResumableDownloadError(
          domain.ValidationFailure.withContext(message: 'bad size'),
        ),
        isFalse,
      );
      expect(
        SilentUpdateInstallerDownload.isResumableDownloadError(
          SilentInstallCancellationFailure(message: 'cancelled'),
        ),
        isFalse,
      );
    });
  });
}

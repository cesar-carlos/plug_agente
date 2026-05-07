import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_failure_localizer.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('maps backupError context codes to ARB strings', () {
    final failure = ValidationFailure.withContext(
      message: 'raw',
      context: {
        LocalBackupErrorCodes.contextKey: LocalBackupErrorCodes.newerBackup,
      },
    );
    expect(localizedBackupFailureMessage(failure, en), en.configBackupErrNewerBackup);
  });

  test('falls back to failure message when code unknown', () {
    final failure = ValidationFailure('only this');
    expect(localizedBackupFailureMessage(failure, en), 'only this');
  });
}

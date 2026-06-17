import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/boot/bootstrap_failure_app.dart';

void main() {
  group('BootstrapFailureMessageBuilder', () {
    final l10n = lookupAppLocalizations(const Locale('pt'));

    test('should return storage guidance for global storage failures', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        const GlobalStorageBootstrapException(
          attempts: <String>[r'C:\ProgramData\PlugAgente -> Access denied'],
        ),
        l10n,
      );

      expect(message.toLowerCase(), contains('diretório global'));
      expect(message.toLowerCase(), contains('administrador'));
    });

    test('should return generic message for non-storage failures', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        StateError('Unexpected bootstrap error'),
        l10n,
      );

      expect(message.toLowerCase(), contains('falha durante a inicialização'));
    });

    test('should return OS guidance when runtime cannot start', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        StateError('Cannot run application: Windows version unsupported'),
        l10n,
      );

      expect(message.toLowerCase(), contains('requisitos mínimos'));
    });

    test('should return ODBC guidance when ODBC initialization fails', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        StateError('ODBC initialization failed during startup: driver missing'),
        l10n,
      );

      expect(message.toLowerCase(), contains('odbc'));
      expect(message.toLowerCase(), contains('driver'));
    });

    test('should append stack trace when available', () {
      final details = BootstrapFailureMessageBuilder.technicalDetails(
        error: const GlobalStorageBootstrapException(
          attempts: <String>[r'C:\ProgramData\PlugAgente -> Access denied'],
        ),
        stackTrace: StackTrace.fromString('trace line'),
      );

      expect(details, contains(GlobalStorageBootstrapException.code));
      expect(details, contains('Access denied'));
      expect(details, contains('trace line'));
    });
  });
}

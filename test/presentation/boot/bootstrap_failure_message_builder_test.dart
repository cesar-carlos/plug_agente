import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/presentation/boot/bootstrap_failure_app.dart';

void main() {
  group('BootstrapFailureMessageBuilder', () {
    test('should return storage guidance for global storage failures', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        const GlobalStorageBootstrapException(
          attempts: <String>[r'C:\ProgramData\PlugAgente -> Access denied'],
        ),
      );

      expect(message.toLowerCase(), contains('diretorio global'));
      expect(message.toLowerCase(), contains('administrador'));
    });

    test('should return generic message for non-storage failures', () {
      final message = BootstrapFailureMessageBuilder.userMessage(
        StateError('Unexpected bootstrap error'),
      );

      expect(message.toLowerCase(), contains('falha durante a inicializacao'));
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

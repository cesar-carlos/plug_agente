import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/error_log_constants.dart';
import 'package:plug_agente/infrastructure/logging/file_log_sink.dart';

void main() {
  group('FileLogSink', () {
    late Directory tempDir;
    late FileLogSink sink;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_log_sink_test');
      sink = FileLogSink(
        logDirectoryPath: tempDir.path,
        maxBytes: 120,
      );
      await sink.open();
    });

    tearDown(() async {
      await sink.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should write structured log lines to the active file', () {
      sink.logStructured(
        level: 'ERROR',
        message: '[NETWORK_ERROR] Hub unavailable',
        error: StateError('offline'),
        context: <String, dynamic>{'operation': 'connect'},
      );

      final contents = File(sink.logFilePath).readAsStringSync();
      expect(contents, contains('ERROR'));
      expect(contents, contains('[NETWORK_ERROR] Hub unavailable'));
      expect(contents, contains('operation'));
      expect(contents, contains('offline'));
    });

    test('should redact sensitive context values', () {
      sink.logStructured(
        level: 'ERROR',
        message: 'Auth failed',
        context: <String, dynamic>{
          'password': 'secret-value',
          'operation': 'login',
        },
      );

      final contents = File(sink.logFilePath).readAsStringSync();
      expect(contents, contains('[REDACTED]'));
      expect(contents, isNot(contains('secret-value')));
    });

    test('should rotate files when max size is exceeded', () {
      for (var index = 0; index < 6; index++) {
        sink.logStructured(
          level: 'ERROR',
          message: 'entry-$index-${'x' * 40}',
        );
      }

      expect(File(sink.logFilePath).existsSync(), isTrue);
      expect(File('${sink.logFilePath}.1').existsSync(), isTrue);
      expect(File('${sink.logFilePath}.2').existsSync(), isTrue);
      expect(File('${sink.logFilePath}.3').existsSync(), isFalse);
    });

    test('relocate should continue logging in the new directory', () async {
      final relocatedDir = p.join(tempDir.path, 'relocated');
      await sink.relocate(relocatedDir);

      sink.logStructured(level: 'WARNING', message: 'after relocate');

      final relocatedFile = File(p.join(relocatedDir, ErrorLogConstants.logFileName));
      expect(relocatedFile.existsSync(), isTrue);
      expect(relocatedFile.readAsStringSync(), contains('after relocate'));
    });
  });
}

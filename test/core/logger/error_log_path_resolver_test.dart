import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/logging/error_log_path_resolver.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

void main() {
  group('ErrorLogPathResolver', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('error_log_path_resolver_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should return first writable early candidate directory', () async {
      final writableCandidate = p.join(tempDir.path, 'early_logs');

      final resolvedDirectory = await ErrorLogPathResolver.resolveWritableLogDirectory(
        candidateDirectories: <String>[writableCandidate],
      );

      expect(resolvedDirectory, writableCandidate);
      expect(Directory(writableCandidate).existsSync(), isTrue);
    });

    test('should skip invalid candidate and use next writable directory', () async {
      final invalidFile = File(p.join(tempDir.path, 'not_a_directory'));
      await invalidFile.writeAsString('locked');
      final writableCandidate = p.join(tempDir.path, 'fallback_logs');

      final resolvedDirectory = await ErrorLogPathResolver.resolveWritableLogDirectory(
        candidateDirectories: <String>[
          invalidFile.path,
          writableCandidate,
        ],
      );

      expect(resolvedDirectory, writableCandidate);
    });

    test('should throw ErrorLogAccessException when all candidates fail', () async {
      final invalidFileOne = File(p.join(tempDir.path, 'invalid_1'));
      final invalidFileTwo = File(p.join(tempDir.path, 'invalid_2'));
      await invalidFileOne.writeAsString('x');
      await invalidFileTwo.writeAsString('y');

      expect(
        () => ErrorLogPathResolver.resolveWritableLogDirectory(
          candidateDirectories: <String>[
            invalidFileOne.path,
            invalidFileTwo.path,
          ],
        ),
        throwsA(isA<ErrorLogAccessException>()),
      );
    });

    test('should prefer temp before program data in early candidate order', () {
      final candidates = <String>[
        p.join(Directory.systemTemp.path, GlobalStoragePathResolver.defaultAppFolderName, 'logs'),
        r'C:\ProgramData\PlugAgente\logs',
      ];

      expect(
        candidates.first,
        contains(GlobalStoragePathResolver.defaultAppFolderName),
      );
      expect(candidates.first.toLowerCase(), isNot(contains('programdata')));
    });

    test('should resolve logs directory from global storage context', () {
      final contextPath = p.join(tempDir.path, 'PlugAgente');
      final logsDirectory = ErrorLogPathResolver.resolveFromGlobalStorage(
        GlobalStorageContext(appDirectoryPath: contextPath),
      );

      expect(logsDirectory, p.join(contextPath, 'logs'));
    });
  });
}

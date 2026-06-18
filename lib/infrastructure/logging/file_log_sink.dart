import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/error_log_constants.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/utils/log_sanitizer.dart';

class FileLogSink implements IStructuredLogSink {
  FileLogSink({
    required String logDirectoryPath,
    this.maxBytes = ErrorLogConstants.maxFileBytes,
    this.maxRotatedFiles = ErrorLogConstants.maxRotatedFiles,
    this.logFileName = ErrorLogConstants.logFileName,
  }) : _logDirectoryPath = logDirectoryPath;

  final int maxBytes;
  final int maxRotatedFiles;
  final String logFileName;

  String _logDirectoryPath;
  RandomAccessFile? _fileHandle;

  String get logDirectoryPath => _logDirectoryPath;

  String get logFilePath => p.join(_logDirectoryPath, logFileName);

  Future<void> open() async {
    final directory = Directory(_logDirectoryPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    _fileHandle = await File(logFilePath).open(mode: FileMode.append);
  }

  Future<void> relocate(String logDirectoryPath) async {
    await close();
    _logDirectoryPath = logDirectoryPath;
    await open();
  }

  Future<void> close() async {
    await _fileHandle?.close();
    _fileHandle = null;
  }

  @override
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    final handle = _fileHandle;
    if (handle == null) {
      return;
    }

    try {
      _rotateIfNeeded();
      final sanitizedContext = context == null || context.isEmpty
          ? null
          : LogSanitizer.sanitizeMap(Map<String, dynamic>.from(context));
      final buffer = StringBuffer()
        ..write(DateTime.now().toUtc().toIso8601String())
        ..write(' ')
        ..write(level)
        ..write(' ')
        ..write(message);
      if (sanitizedContext != null) {
        buffer
          ..write(' | context=')
          ..write(jsonEncode(sanitizedContext));
      }
      if (error != null) {
        buffer
          ..write(' | error=')
          ..write(error);
      }
      if (stackTrace != null) {
        buffer
          ..write(' | stack=')
          ..write(stackTrace);
      }
      buffer.writeln();
      handle.writeStringSync(buffer.toString());
      handle.flushSync();
    } on Object {
      // File logging must never crash the caller.
    }
  }

  void _rotateIfNeeded() {
    final file = File(logFilePath);
    if (!file.existsSync()) {
      return;
    }
    if (file.lengthSync() < maxBytes) {
      return;
    }

    _fileHandle?.closeSync();
    _fileHandle = null;

    final oldestPath = '$logFilePath.${maxRotatedFiles - 1}';
    final oldest = File(oldestPath);
    if (oldest.existsSync()) {
      oldest.deleteSync();
    }

    for (var index = maxRotatedFiles - 2; index >= 1; index--) {
      final source = File('$logFilePath.$index');
      if (source.existsSync()) {
        source.renameSync('$logFilePath.${index + 1}');
      }
    }

    if (file.existsSync()) {
      file.renameSync('$logFilePath.1');
    }

    _fileHandle = File(logFilePath).openSync(mode: FileMode.append);
  }
}

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logging/composite_log_sink.dart';
import 'package:plug_agente/core/logging/console_structured_log_sink.dart';
import 'package:plug_agente/core/logging/error_log_path_resolver.dart';
import 'package:plug_agente/core/services/error_tracker.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';
import 'package:plug_agente/domain/logging/structured_log_sink_registry.dart';
import 'package:plug_agente/infrastructure/logging/file_log_sink.dart';

class ErrorLoggingBootstrap {
  ErrorLoggingBootstrap._();

  static CompositeLogSink? _compositeSink;
  static FileLogSink? _fileSink;

  static IStructuredLogSink? get compositeSink => _compositeSink;

  static String? get activeLogFilePath => _fileSink?.logFilePath;

  static Future<void> initializeEarly({
    List<String>? candidateLogDirectories,
  }) async {
    if (_compositeSink != null) {
      return;
    }

    try {
      final directory = await ErrorLogPathResolver.resolveWritableLogDirectory(
        candidateDirectories: candidateLogDirectories,
      );
      await _openCompositeSink(directory);
    } on ErrorLogAccessException {
      AppLogger.warning('Early error log directory unavailable; console-only logging until storage resolves');
    }
  }

  static Future<void> upgradeToAppStorage(GlobalStorageContext context) async {
    final directory = ErrorLogPathResolver.resolveFromGlobalStorage(context);
    if (_fileSink == null) {
      await _openCompositeSink(directory);
      return;
    }

    if (_fileSink!.logDirectoryPath == directory) {
      return;
    }

    await _fileSink!.relocate(directory);
  }

  static Future<void> registerErrorTracker({
    String dsn = '',
    String environment = 'development',
    String release = '',
    Map<String, dynamic> tags = const {},
  }) async {
    await ErrorTracker.initialize(
      dsn: dsn,
      environment: environment,
      release: release,
      tags: tags,
      sink: _compositeSink,
    );
  }

  static Future<void> _openCompositeSink(String directory) async {
    final fileSink = FileLogSink(logDirectoryPath: directory);
    await fileSink.open();
    final compositeSink = CompositeLogSink(
      fileSink: fileSink,
      consoleSink: ConsoleStructuredLogSink(),
    );
    _fileSink = fileSink;
    _compositeSink = compositeSink;
    StructuredLogSinkRegistry.register(compositeSink);
    AppLogger.attachStructuredSink(compositeSink);
  }

  static Future<void> dispose() async {
    AppLogger.detachStructuredSink();
    StructuredLogSinkRegistry.reset();
    await _fileSink?.close();
    _fileSink = null;
    _compositeSink = null;
  }
}

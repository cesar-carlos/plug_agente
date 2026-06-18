abstract class IStructuredLogSink {
  void logStructured({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  });
}

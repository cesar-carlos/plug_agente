class StartupServiceFailure implements Exception {
  const StartupServiceFailure({
    required this.message,
    this.cause,
  });

  final String message;
  final Exception? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'StartupServiceFailure: $message (causa: $cause)';
    }
    return 'StartupServiceFailure: $message';
  }
}

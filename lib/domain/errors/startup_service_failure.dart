enum StartupServiceFailureCode {
  unknown,
  uacCancelled,
  accessDenied,
  registryDeleteFailed,
  registryWriteFailed,
  unsupportedPlatform,
}

class StartupServiceFailure implements Exception {
  const StartupServiceFailure({
    required this.message,
    this.code = StartupServiceFailureCode.unknown,
    this.registryScopeLabel,
    this.cause,
  });

  final String message;
  final StartupServiceFailureCode code;
  final String? registryScopeLabel;
  final Exception? cause;

  @override
  String toString() {
    final scopeSuffix = registryScopeLabel != null ? ' [$registryScopeLabel]' : '';
    if (cause != null) {
      return 'StartupServiceFailure($code$scopeSuffix): $message (cause: $cause)';
    }
    return 'StartupServiceFailure($code$scopeSuffix): $message';
  }
}

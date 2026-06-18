class ErrorLogConstants {
  ErrorLogConstants._();

  static const String logFileName = 'plug_agente_errors.log';
  static const String logsSubdirectory = 'logs';
  static const int maxFileBytes = 5 * 1024 * 1024;
  static const int maxRotatedFiles = 3;
}

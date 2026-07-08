import 'package:plug_agente/domain/errors/failures.dart';

enum StartupServiceFailureCode {
  unknown,
  uacCancelled,
  accessDenied,
  registryDeleteFailed,
  registryWriteFailed,
  registryReadFailed,
  unsupportedPlatform,
}

class StartupServiceFailure extends ConfigurationFailure {
  StartupServiceFailure({
    required super.message,
    this.startupCode = StartupServiceFailureCode.unknown,
    String? registryScopeLabel,
    super.cause,
    int? nativeStatus,
  }) : super.withContext(
         context: {
           'registry_scope': ?registryScopeLabel,
           'startup_failure_code': startupCode.name,
           'native_status': ?nativeStatus,
         },
         code: 'STARTUP_${startupCode.name.toUpperCase()}',
       );

  final StartupServiceFailureCode startupCode;

  String? get registryScopeLabel => context['registry_scope'] as String?;

  int? get nativeStatus => context['native_status'] as int?;

  @override
  bool get isTransient => startupCode == StartupServiceFailureCode.uacCancelled;

  @override
  String toString() {
    final scopeSuffix = registryScopeLabel != null ? ' [$registryScopeLabel]' : '';
    if (cause != null) {
      return 'StartupServiceFailure($startupCode$scopeSuffix): $message (cause: $cause)';
    }
    return 'StartupServiceFailure($startupCode$scopeSuffix): $message';
  }
}

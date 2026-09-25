import 'package:plug_agente/core/config/app_environment.dart';

const String odbcNativePoolSessionResetOnCheckoutEnvKey = 'ODBC_NATIVE_POOL_SESSION_RESET_ON_CHECKOUT';

/// `null` keeps the engine default (`true`). Checkin reset stays unconditional
/// even when checkout reset is disabled.
bool? readOdbcNativePoolSessionResetOnCheckoutOverride({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcNativePoolSessionResetOnCheckoutEnvKey))
      ?.trim()
      .toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
    return true;
  }
  if (normalized == '0' || normalized == 'false' || normalized == 'no') {
    return false;
  }
  return null;
}

import 'package:plug_agente/core/config/app_environment.dart';

const String odbcNativePoolTestOnCheckoutEnvKey = 'ODBC_NATIVE_POOL_TEST_ON_CHECKOUT';

bool? readOdbcNativePoolTestOnCheckoutOverride({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcNativePoolTestOnCheckoutEnvKey))
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

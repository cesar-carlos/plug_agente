import 'package:plug_agente/core/di/service_locator.dart';

/// Resolves an optional application service from getIt without using Provider.
T? readOptionalGetItService<T extends Object>() {
  if (!getIt.isRegistered<T>()) {
    return null;
  }
  return getIt<T>();
}

/// Resolves a required application service from getIt.
T readGetItService<T extends Object>() {
  return getIt<T>();
}

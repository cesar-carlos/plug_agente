import 'dart:io' as io;

import 'package:plug_agente/core/di/get_it.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_runtime_reloader.dart';

Future<bool> reloadOdbcRuntimeDependencies() async {
  if (!getIt.isRegistered<IOdbcRuntimeReloader>()) {
    return false;
  }
  return getIt<IOdbcRuntimeReloader>().reload();
}

OdbcRuntimeTuning resolveOdbcRuntimeTuning({
  required IOdbcConnectionSettings settings,
  int? processorCount,
}) {
  return OdbcRuntimeTuning.forPoolSize(
    poolSize: settings.poolSize,
    processorCount: processorCount ?? io.Platform.numberOfProcessors,
  );
}

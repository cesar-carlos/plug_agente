import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:plug_agente/presentation/boot/app_root.dart';
import 'package:plug_agente/presentation/boot/bootstrap_failure_app.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final initializer = AppInitializer(runtimeProbe: WindowsRuntimeProbe());
    final bootstrapData = await initializer.initialize(args);
    runApp(
      AppRoot(
        initialRoute: bootstrapData.initialRoute,
        capabilities: bootstrapData.capabilities,
      ),
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'Bootstrap failed before runApp',
      name: 'main',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    try {
      await shutdownApp();
    } on Object catch (shutdownError, shutdownStackTrace) {
      developer.log(
        'Bootstrap failure cleanup also failed',
        name: 'main',
        level: 1000,
        error: shutdownError,
        stackTrace: shutdownStackTrace,
      );
    }

    runApp(
      BootstrapFailureApp(
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

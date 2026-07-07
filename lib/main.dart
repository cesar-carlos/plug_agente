import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logging/error_logging_bootstrap.dart';
import 'package:plug_agente/core/services/error_tracker.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:plug_agente/presentation/boot/app_root.dart';
import 'package:plug_agente/presentation/boot/bootstrap_failure_app.dart';

Future<void> main(List<String> args) async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await ErrorLoggingBootstrap.initializeEarly();
      _installGlobalErrorHandlers();

      try {
        final initializer = AppInitializer(runtimeProbe: WindowsRuntimeProbe());
        final bootstrapData = await initializer.initialize(args);
        runApp(
          AppRoot(
            initialRoute: bootstrapData.initialRoute,
            capabilities: bootstrapData.capabilities,
            runDeferredBootstrap: bootstrapData.runDeferredBootstrap,
          ),
        );
      } on Object catch (error, stackTrace) {
        _logBootstrapFailure(error, stackTrace);
        try {
          await shutdownApp();
        } on Object catch (shutdownError, shutdownStackTrace) {
          ErrorTracker.captureException(
            shutdownError,
            shutdownStackTrace,
            operation: 'bootstrap_failure_cleanup',
          );
        }

        try {
          await getIt.reset();
        } on Object catch (resetError, resetStackTrace) {
          ErrorTracker.captureException(
            resetError,
            resetStackTrace,
            operation: 'bootstrap_failure_dependency_reset',
          );
        }

        runApp(
          BootstrapFailureApp(
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    },
    (error, stackTrace) {
      ErrorTracker.captureException(
        error,
        stackTrace,
        operation: 'zone_uncaught',
        fatal: true,
      );
    },
  );
}

void _installGlobalErrorHandlers() {
  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorTracker.captureException(
      details.exception,
      details.stack ?? StackTrace.empty,
      operation: 'flutter_error',
      context: <String, dynamic>{
        if (details.library != null) 'library': details.library,
        if (details.context != null) 'context': details.context.toString(),
      },
    );
    previousFlutterOnError?.call(details);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorTracker.captureException(
      error,
      stack,
      operation: 'platform_dispatcher',
      fatal: true,
    );
    return previousPlatformOnError?.call(error, stack) ?? true;
  };
}

void _logBootstrapFailure(Object error, StackTrace stackTrace) {
  ErrorTracker.captureException(
    error,
    stackTrace,
    operation: 'bootstrap_before_run_app',
    fatal: true,
  );
  developer.log(
    'Bootstrap failed before runApp',
    name: 'main',
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );
}

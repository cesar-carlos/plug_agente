import 'dart:io' as io;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

odbc.ServiceLocator createAsyncOdbcServiceLocatorForSettings(
  IOdbcConnectionSettings settings,
) {
  final tuning = OdbcRuntimeTuning.forPoolSize(
    poolSize: settings.poolSize,
    processorCount: io.Platform.numberOfProcessors,
  );
  return odbc.ServiceLocator()..initialize(
    useAsync: true,
    asyncWorkerCount: tuning.asyncWorkerCount,
    asyncMaxPendingRequests: tuning.asyncMaxPendingRequests,
    // Keep E2E harnesses aligned with the production ODBC tuning contract.
    asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
  );
}

class MockOdbcConnectionSettings implements IOdbcConnectionSettings {
  MockOdbcConnectionSettings({
    this.poolSize = ConnectionConstants.defaultPoolSize,
    this.loginTimeoutSeconds = 30,
    this.maxResultBufferMb = ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024),
    this.streamingChunkSizeKb = 1024,
    this.useNativeOdbcPool = false,
    this.nativePoolTestOnCheckout = true,
  });

  @override
  int poolSize;

  @override
  int loginTimeoutSeconds;

  @override
  int maxResultBufferMb;

  @override
  int streamingChunkSizeKb;

  @override
  bool useNativeOdbcPool;

  @override
  bool nativePoolTestOnCheckout;

  @override
  Future<void> load() async {}

  @override
  Future<void> setPoolSize(int value) async => poolSize = value;

  @override
  Future<void> setLoginTimeoutSeconds(int value) async => loginTimeoutSeconds = value;

  @override
  Future<void> setMaxResultBufferMb(int value) async => maxResultBufferMb = value;

  @override
  Future<void> setStreamingChunkSizeKb(int value) async => streamingChunkSizeKb = value;

  @override
  Future<void> setUseNativeOdbcPool(bool value) async => useNativeOdbcPool = value;

  @override
  Future<void> setNativePoolTestOnCheckout(bool value) async => nativePoolTestOnCheckout = value;
}

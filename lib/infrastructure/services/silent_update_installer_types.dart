import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

typedef DioFactoryFn = Dio Function();
typedef HttpClientFactory = HttpClient Function();
typedef SilentUpdateProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });
typedef InstallDirectoryResolver = Future<String> Function();
typedef InstallDirectoryWritableProbe = Future<bool> Function(String installDirectory);
typedef UpdateHelperPathResolver = Future<String> Function();
typedef CurrentProcessIdResolver = int Function();
typedef UpdateDirectorySecurityHardener = Future<String> Function(String updateDirectory);
typedef DiskFreeSpaceResolver = Future<int?> Function(String directoryPath);

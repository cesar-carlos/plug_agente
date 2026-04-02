import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/infrastructure/http/get_retry_interceptor.dart';

class DioFactory {
  static String? _userAgent;
  static bool _isInitializing = false;

  static const String _envKeyAcceptBadCertificates = 'ACCEPT_BAD_CERTIFICATES';

  static Future<String> _getUserAgent() async {
    if (_userAgent != null) {
      return _userAgent!;
    }

    if (_isInitializing) {
      while (_userAgent == null) {
        await Future<void>.delayed(
          const Duration(
            milliseconds: AppConstants.userAgentInitPollIntervalMs,
          ),
        );
      }
      return _userAgent!;
    }

    _isInitializing = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _userAgent = '${AppConstants.appName}/${packageInfo.version} (Windows)';
    } on Exception catch (e, stackTrace) {
      developer.log(
        'PackageInfo.fromPlatform failed, using fallback User-Agent',
        name: 'dio_factory',
        error: e,
        stackTrace: stackTrace,
      );
      _userAgent = '${AppConstants.appName}/${AppConstants.appVersion} (Windows)';
    } finally {
      _isInitializing = false;
    }

    return _userAgent!;
  }

  static bool _shouldAcceptBadCertificates() {
    try {
      final envValue = dotenv.env[_envKeyAcceptBadCertificates];
      return envValue?.toLowerCase() == 'true' || envValue == '1';
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to read ACCEPT_BAD_CERTIFICATES env, defaulting to false',
        name: 'dio_factory',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  static Dio createDio({
    bool? acceptBadCertificates,
    Duration? requestTimeout,
  }) {
    final shouldAccept = acceptBadCertificates ?? _shouldAcceptBadCertificates();
    final timeout = requestTimeout ?? const Duration(seconds: AppConstants.connectionTimeoutSeconds);

    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': '${AppConstants.appName}/${AppConstants.appVersion} (Windows)',
        },
        persistentConnection: true,
        followRedirects: true,
      ),
    );

    final adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()..autoUncompress = true;
        if (shouldAccept) {
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        }
        return client;
      },
    );
    dio.httpClientAdapter = adapter;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final userAgent = await _getUserAgent();
          options.headers['User-Agent'] = userAgent;
          return handler.next(options);
        },
      ),
    );

    dio.interceptors.add(LogInterceptor());
    dio.interceptors.add(GetRetryInterceptor(dio: dio));

    return dio;
  }
}

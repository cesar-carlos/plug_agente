import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/app_constants.dart';

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
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return _userAgent!;
    }

    _isInitializing = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _userAgent = '${AppConstants.appName}/${packageInfo.version} (Windows)';
    } catch (e) {
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
    } catch (e) {
      return false;
    }
  }

  static Dio createDio({bool? acceptBadCertificates}) {
    final shouldAccept = acceptBadCertificates ?? _shouldAcceptBadCertificates();

    final dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: AppConstants.connectionTimeoutSeconds),
        receiveTimeout: Duration(seconds: AppConstants.connectionTimeoutSeconds),
        sendTimeout: Duration(seconds: AppConstants.connectionTimeoutSeconds),
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
        final client = HttpClient();
        client.autoUncompress = true;
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

    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: true,
        error: true,
      ),
    );

    return dio;
  }
}

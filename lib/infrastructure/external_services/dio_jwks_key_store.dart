import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:jose/jose.dart';

/// Loads remote keys without JOSE's global HTTP response cache.
class DioJwksKeyStore extends JsonWebKeyStore {
  DioJwksKeyStore(this._uri, {Duration requestTimeout = _defaultRequestTimeout}) : _requestTimeout = requestTimeout;

  static const _defaultRequestTimeout = Duration(seconds: 5);
  final Duration _requestTimeout;
  final Uri _uri;
  JsonWebKeyStore? _loaded;
  Future<JsonWebKeyStore>? _loading;

  @override
  Stream<JsonWebKey?> findJsonWebKeys(JoseHeader header, String operation) async* {
    final store = _loaded ?? await (_loading ??= _loadStore());
    yield* store.findJsonWebKeys(header, operation);
  }

  Future<JsonWebKeyStore> _loadStore() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: _requestTimeout,
        receiveTimeout: _requestTimeout,
        sendTimeout: _requestTimeout,
        responseType: ResponseType.plain,
        headers: const {'Accept': 'application/json'},
      ),
    );
    final cancellation = CancelToken();
    try {
      final response = await dio
          .getUri<String>(_uri, cancelToken: cancellation)
          .timeout(
            _requestTimeout,
            onTimeout: () {
              cancellation.cancel('JWKS request timed out');
              throw const FormatException('JWKS request timed out');
            },
          );
      if (response.statusCode != 200) throw const FormatException('JWKS request failed');
      final decoded = jsonDecode(response.data ?? '');
      if (decoded is! Map<String, dynamic>) throw const FormatException('JWKS must be an object');
      final keys = decoded['keys'];
      if (keys is! List || keys.isEmpty) throw const FormatException('JWKS keys must be a nonempty list');
      final store = JsonWebKeyStore();
      for (final key in keys) {
        if (key is! Map<String, dynamic>) throw const FormatException('Invalid JWKS key');
        _validateKey(key);
        store.addKey(JsonWebKey.fromJson(key));
      }
      _loaded = store;
      return store;
    } on DioException {
      // Network errors can contain response bodies; keep the failure safe.
      throw const FormatException('Failed to fetch JWKS');
    } on FormatException {
      throw const FormatException('Failed to load a valid JWKS response');
    } finally {
      _loading = null;
      dio.close(force: true);
    }
  }

  void _validateKey(Map<String, dynamic> key) {
    for (final field in ['kty', 'kid', 'use', 'alg', 'crv', 'x5u', 'x5t', 'x5t#S256']) {
      if (key.containsKey(field) && key[field] is! String) throw const FormatException('Invalid JWK metadata');
    }
    for (final field in ['key_ops', 'x5c']) {
      final value = key[field];
      if (key.containsKey(field) && (value is! List || value.any((item) => item is! String))) {
        throw const FormatException('Invalid JWK metadata');
      }
    }
    final requiredFields = switch (key['kty']) {
      'RSA' => ['n', 'e'],
      'EC' => ['crv', 'x', 'y'],
      'oct' => ['k'],
      _ => throw const FormatException('Unsupported JWK key type'),
    };
    for (final field in requiredFields) {
      final value = key[field];
      if (value is! String || value.isEmpty) throw const FormatException('Missing JWK key material');
    }
    if (key['kty'] == 'EC' && !['P-256', 'P-256K', 'P-384', 'P-521'].contains(key['crv'])) {
      throw const FormatException('Unsupported JWK curve');
    }
    for (final field in ['n', 'e', 'x', 'y', 'd', 'p', 'q', 'dp', 'dq', 'qi', 'k']) {
      if (!key.containsKey(field)) continue;
      final value = key[field];
      if (value is! String || base64Url.decode(base64Url.normalize(value)).isEmpty) {
        throw const FormatException('Invalid JWK key material');
      }
    }
  }
}

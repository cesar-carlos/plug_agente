import 'package:shared_preferences/shared_preferences.dart';

/// Feature flags for controlling rollout and experimentation.
class FeatureFlags {
  FeatureFlags(this._prefs);

  final SharedPreferences _prefs;

  // Keys
  static const _keyEnableJsonRpcV2 = 'feature_enable_jsonrpc_v2';
  static const _keyEnableBinaryPayload = 'feature_enable_binary_payload';
  static const _keyEnableCompression = 'feature_enable_compression';
  static const _keyCompressionThreshold = 'feature_compression_threshold';
  static const _keyAutoFallbackToLegacy = 'feature_auto_fallback_legacy';
  static const _keyEnableClientTokenAuthorization =
      'feature_enable_client_token_authorization';

  /// Whether JSON-RPC v2 protocol is enabled.
  bool get enableJsonRpcV2 => _prefs.getBool(_keyEnableJsonRpcV2) ?? false;

  Future<void> setEnableJsonRpcV2(bool value) async {
    await _prefs.setBool(_keyEnableJsonRpcV2, value);
  }

  /// Whether binary payload is enabled.
  bool get enableBinaryPayload =>
      _prefs.getBool(_keyEnableBinaryPayload) ?? false;

  Future<void> setEnableBinaryPayload(bool value) async {
    await _prefs.setBool(_keyEnableBinaryPayload, value);
  }

  /// Whether compression is enabled.
  bool get enableCompression => _prefs.getBool(_keyEnableCompression) ?? true;

  Future<void> setEnableCompression(bool value) async {
    await _prefs.setBool(_keyEnableCompression, value);
  }

  /// Compression threshold in bytes.
  int get compressionThreshold =>
      _prefs.getInt(_keyCompressionThreshold) ?? 1024;

  Future<void> setCompressionThreshold(int value) async {
    await _prefs.setInt(_keyCompressionThreshold, value);
  }

  /// Whether to automatically fallback to legacy protocol on error.
  bool get autoFallbackToLegacy =>
      _prefs.getBool(_keyAutoFallbackToLegacy) ?? true;

  Future<void> setAutoFallbackToLegacy(bool value) async {
    await _prefs.setBool(_keyAutoFallbackToLegacy, value);
  }

  /// Whether client token authorization is enabled (enforcement before SQL).
  bool get enableClientTokenAuthorization =>
      _prefs.getBool(_keyEnableClientTokenAuthorization) ?? false;

  Future<void> setEnableClientTokenAuthorization(bool value) async {
    await _prefs.setBool(_keyEnableClientTokenAuthorization, value);
  }

  /// Resets all feature flags to default values.
  Future<void> resetToDefaults() async {
    await setEnableJsonRpcV2(false);
    await setEnableBinaryPayload(false);
    await setEnableCompression(true);
    await setCompressionThreshold(1024);
    await setAutoFallbackToLegacy(true);
    await setEnableClientTokenAuthorization(false);
  }
}

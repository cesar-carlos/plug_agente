import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

const _keyPoolSize = 'odbc_pool_size';
const _keyPoolSizeUserConfigured = 'odbc_pool_size_user_configured';
const _keyLoginTimeoutSeconds = 'odbc_login_timeout_seconds';
const _keyMaxResultBufferMb = 'odbc_max_result_buffer_mb';
const _keyStreamingChunkSizeKb = 'odbc_streaming_chunk_size_kb';
const _keyUseNativeOdbcPool = 'odbc_use_native_pool';
const _keyNativePoolTestOnCheckout = 'odbc_native_pool_test_on_checkout';

/// Implementacao de [IOdbcConnectionSettings] com store global de configuracoes.
class OdbcConnectionSettings implements IOdbcConnectionSettings {
  OdbcConnectionSettings(this._prefs);
  final IAppSettingsStore _prefs;

  /// Previous factory default before benchmark tuning raised [ConnectionConstants.defaultPoolSize].
  static const int legacyFactoryDefaultPoolSize = 4;

  // Allowed ranges (mirror the UI constraints in odbc_connection_pool_section).
  static const int _minPoolSize = 1;
  static const int _maxPoolSize = 20;
  static const int _minLoginTimeoutSeconds = 1;
  static const int _maxLoginTimeoutSeconds = 120;
  static const int _minMaxResultBufferMb = 8;
  static const int _maxMaxResultBufferMb = 128;
  static const int _minStreamingChunkSizeKb = 64;
  static const int _maxStreamingChunkSizeKb = 32 * 1024;

  static int _clampPoolSize(int v) => v.clamp(_minPoolSize, _maxPoolSize);
  static int _clampLoginTimeout(int v) => v.clamp(_minLoginTimeoutSeconds, _maxLoginTimeoutSeconds);
  static int _clampMaxResultBuffer(int v) => v.clamp(_minMaxResultBufferMb, _maxMaxResultBufferMb);
  static int _clampStreamingChunk(int v) => v.clamp(_minStreamingChunkSizeKb, _maxStreamingChunkSizeKb);

  int _poolSize = ConnectionConstants.defaultPoolSize;
  int _loginTimeoutSeconds = ConnectionConstants.defaultLoginTimeout.inSeconds;
  int _maxResultBufferMb = ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024);
  int _streamingChunkSizeKb = ConnectionConstants.defaultStreamingChunkSizeKb;
  bool _useNativeOdbcPool = false;
  bool _nativePoolTestOnCheckout = true;

  @override
  int get poolSize => _poolSize;

  @override
  int get loginTimeoutSeconds => _loginTimeoutSeconds;

  @override
  int get maxResultBufferMb => _maxResultBufferMb;

  @override
  int get streamingChunkSizeKb => _streamingChunkSizeKb;

  @override
  bool get useNativeOdbcPool => _useNativeOdbcPool;

  @override
  bool get nativePoolTestOnCheckout => _nativePoolTestOnCheckout;

  @override
  Future<void> load() async {
    // Clamp values on load so manually edited settings.json or legacy imports
    // can never drive the pool semaphore or connection options out of range.
    _poolSize = await _loadPoolSize();
    _loginTimeoutSeconds = _clampLoginTimeout(
      _prefs.getInt(_keyLoginTimeoutSeconds) ?? ConnectionConstants.defaultLoginTimeout.inSeconds,
    );
    _maxResultBufferMb = _clampMaxResultBuffer(
      _prefs.getInt(_keyMaxResultBufferMb) ?? (ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024)),
    );
    _streamingChunkSizeKb = _clampStreamingChunk(
      _prefs.getInt(_keyStreamingChunkSizeKb) ?? ConnectionConstants.defaultStreamingChunkSizeKb,
    );
    _useNativeOdbcPool = _prefs.getBool(_keyUseNativeOdbcPool) ?? false;
    _nativePoolTestOnCheckout = _prefs.getBool(_keyNativePoolTestOnCheckout) ?? true;
  }

  Future<int> _loadPoolSize() async {
    final persisted = _prefs.getInt(_keyPoolSize);
    if (persisted == null) {
      return _clampPoolSize(ConnectionConstants.poolSize);
    }

    final clamped = _clampPoolSize(persisted);
    final userConfigured = _prefs.getBool(_keyPoolSizeUserConfigured) ?? false;
    if (clamped == legacyFactoryDefaultPoolSize &&
        !userConfigured &&
        ConnectionConstants.defaultPoolSize != legacyFactoryDefaultPoolSize) {
      await _prefs.setInt(_keyPoolSize, ConnectionConstants.defaultPoolSize);
      return ConnectionConstants.defaultPoolSize;
    }

    return clamped;
  }

  @override
  Future<void> setPoolSize(int value) async {
    final clamped = _clampPoolSize(value);
    await _prefs.setValues({
      _keyPoolSize: clamped,
      _keyPoolSizeUserConfigured: true,
    });
    _poolSize = clamped;
  }

  @override
  Future<void> setLoginTimeoutSeconds(int value) async {
    final clamped = _clampLoginTimeout(value);
    await _prefs.setInt(_keyLoginTimeoutSeconds, clamped);
    _loginTimeoutSeconds = clamped;
  }

  @override
  Future<void> setMaxResultBufferMb(int value) async {
    final clamped = _clampMaxResultBuffer(value);
    await _prefs.setInt(_keyMaxResultBufferMb, clamped);
    _maxResultBufferMb = clamped;
  }

  @override
  Future<void> setStreamingChunkSizeKb(int value) async {
    final clamped = _clampStreamingChunk(value);
    await _prefs.setInt(_keyStreamingChunkSizeKb, clamped);
    _streamingChunkSizeKb = clamped;
  }

  @override
  Future<void> setUseNativeOdbcPool(bool value) async {
    await _prefs.setBool(_keyUseNativeOdbcPool, value);
    _useNativeOdbcPool = value;
  }

  @override
  Future<void> setNativePoolTestOnCheckout(bool value) async {
    await _prefs.setBool(_keyNativePoolTestOnCheckout, value);
    _nativePoolTestOnCheckout = value;
  }
}

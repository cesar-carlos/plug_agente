import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyPoolSize = 'odbc_pool_size';
const _keyLoginTimeoutSeconds = 'odbc_login_timeout_seconds';
const _keyMaxResultBufferMb = 'odbc_max_result_buffer_mb';
const _keyStreamingChunkSizeKb = 'odbc_streaming_chunk_size_kb';

/// Implementação de [IOdbcConnectionSettings] usando SharedPreferences.
class OdbcConnectionSettings implements IOdbcConnectionSettings {
  OdbcConnectionSettings(this._prefs);
  final SharedPreferences _prefs;

  int _poolSize = ConnectionConstants.defaultPoolSize;
  int _loginTimeoutSeconds =
      ConnectionConstants.defaultLoginTimeout.inSeconds;
  int _maxResultBufferMb =
      ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024);
  int _streamingChunkSizeKb = ConnectionConstants.defaultStreamingChunkSizeKb;

  @override
  int get poolSize => _poolSize;

  @override
  int get loginTimeoutSeconds => _loginTimeoutSeconds;

  @override
  int get maxResultBufferMb => _maxResultBufferMb;

  @override
  int get streamingChunkSizeKb => _streamingChunkSizeKb;

  @override
  Future<void> load() async {
    _poolSize = _prefs.getInt(_keyPoolSize) ?? ConnectionConstants.defaultPoolSize;
    _loginTimeoutSeconds = _prefs.getInt(_keyLoginTimeoutSeconds) ??
        ConnectionConstants.defaultLoginTimeout.inSeconds;
    _maxResultBufferMb = _prefs.getInt(_keyMaxResultBufferMb) ??
        (ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024));
    _streamingChunkSizeKb =
        _prefs.getInt(_keyStreamingChunkSizeKb) ??
        ConnectionConstants.defaultStreamingChunkSizeKb;
  }

  @override
  Future<void> setPoolSize(int value) async {
    await _prefs.setInt(_keyPoolSize, value);
    _poolSize = value;
  }

  @override
  Future<void> setLoginTimeoutSeconds(int value) async {
    await _prefs.setInt(_keyLoginTimeoutSeconds, value);
    _loginTimeoutSeconds = value;
  }

  @override
  Future<void> setMaxResultBufferMb(int value) async {
    await _prefs.setInt(_keyMaxResultBufferMb, value);
    _maxResultBufferMb = value;
  }

  @override
  Future<void> setStreamingChunkSizeKb(int value) async {
    await _prefs.setInt(_keyStreamingChunkSizeKb, value);
    _streamingChunkSizeKb = value;
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runtime canary probe for Windows secure storage with TTL-cached results.
final class SecureStorageRuntimeProbe {
  SecureStorageRuntimeProbe({
    FlutterSecureStorage? secureStorage,
    Duration? cacheTtl,
    DateTime Function()? nowProvider,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _cacheTtl = cacheTtl ?? const Duration(minutes: 5),
       _nowProvider = nowProvider ?? DateTime.now;

  static const String _canaryKey = 'plug_agente_secure_storage_health_probe';

  final FlutterSecureStorage _secureStorage;
  final Duration _cacheTtl;
  final DateTime Function() _nowProvider;

  DateTime? _lastProbeAt;
  bool? _lastProbeOk;
  String? _lastProbeError;

  DateTime? get lastProbeAt => _lastProbeAt;

  bool? get lastProbeOk => _lastProbeOk;

  String? get lastProbeError => _lastProbeError;

  Future<bool> probe({bool forceRefresh = false}) async {
    final now = _nowProvider();
    if (!forceRefresh &&
        _lastProbeAt != null &&
        _lastProbeOk != null &&
        now.difference(_lastProbeAt!) < _cacheTtl) {
      return _lastProbeOk!;
    }

    try {
      const canaryValue = 'probe';
      await _secureStorage.write(key: _canaryKey, value: canaryValue);
      final readValue = await _secureStorage.read(key: _canaryKey);
      await _secureStorage.delete(key: _canaryKey);

      final ok = readValue == canaryValue;
      _lastProbeAt = now;
      _lastProbeOk = ok;
      _lastProbeError = ok ? null : 'canary read mismatch';
      return ok;
    } on Object catch (error) {
      _lastProbeAt = now;
      _lastProbeOk = false;
      _lastProbeError = error.toString();
      return false;
    }
  }
}

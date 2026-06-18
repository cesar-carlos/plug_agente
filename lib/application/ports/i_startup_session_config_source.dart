import 'package:plug_agente/domain/entities/config.dart';

/// Read-only config snapshot for startup auto-session flows.
abstract interface class IStartupSessionConfigSource {
  bool get isLoading;

  Config? get currentConfig;
}

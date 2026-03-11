import 'package:plug_agente/core/runtime/runtime_mode.dart';

/// Capacidades disponíveis no ambiente de execução atual.
class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.mode,
    required this.supportsTray,
    required this.supportsNotifications,
    required this.supportsAutoUpdate,
    required this.supportsWindowManager,
    this.degradationReasons = const [],
  });

  /// Capacidades completas (Windows 10/11 cliente).
  factory RuntimeCapabilities.full() {
    return const RuntimeCapabilities(
      mode: RuntimeMode.full,
      supportsTray: true,
      supportsNotifications: true,
      supportsAutoUpdate: true,
      supportsWindowManager: true,
    );
  }

  /// Capacidades degradadas (Server 2012/2012 R2, Server 2016+).
  factory RuntimeCapabilities.degraded({
    required List<String> reasons,
  }) {
    return RuntimeCapabilities(
      mode: RuntimeMode.degraded,
      supportsTray: false,
      supportsNotifications: false,
      supportsAutoUpdate: false,
      supportsWindowManager: true,
      degradationReasons: reasons,
    );
  }

  /// Ambiente não suportado (< Windows 8 / < Server 2012).
  factory RuntimeCapabilities.unsupported({
    required List<String> reasons,
  }) {
    return RuntimeCapabilities(
      mode: RuntimeMode.unsupported,
      supportsTray: false,
      supportsNotifications: false,
      supportsAutoUpdate: false,
      supportsWindowManager: false,
      degradationReasons: reasons,
    );
  }

  final RuntimeMode mode;
  final bool supportsTray;
  final bool supportsNotifications;
  final bool supportsAutoUpdate;
  final bool supportsWindowManager;
  final List<String> degradationReasons;

  bool get isFullySupported => mode.isFullySupported;
  bool get isDegraded => mode.isDegraded;
  bool get isUnsupported => mode.isUnsupported;
  bool get canRunCore => mode.canRunCore;

  @override
  String toString() {
    return 'RuntimeCapabilities('
        'mode: ${mode.displayName}, '
        'tray: $supportsTray, '
        'notifications: $supportsNotifications, '
        'autoUpdate: $supportsAutoUpdate, '
        'windowManager: $supportsWindowManager'
        '${degradationReasons.isNotEmpty ? ', reasons: $degradationReasons' : ''}'
        ')';
  }
}

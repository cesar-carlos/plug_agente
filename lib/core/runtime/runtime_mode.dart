/// Modo de execução do aplicativo baseado em capacidades do SO.
enum RuntimeMode {
  /// Modo completo com todos os recursos disponíveis.
  full,

  /// Modo degradado com recursos limitados mas funcionais.
  degraded,

  /// Ambiente não suportado (não deve inicializar recursos críticos).
  unsupported,
}

extension RuntimeModeExtension on RuntimeMode {
  bool get isFullySupported => this == RuntimeMode.full;
  bool get isDegraded => this == RuntimeMode.degraded;
  bool get isUnsupported => this == RuntimeMode.unsupported;
  bool get canRunCore => this != RuntimeMode.unsupported;

  String get displayName {
    switch (this) {
      case RuntimeMode.full:
        return 'Completo';
      case RuntimeMode.degraded:
        return 'Degradado';
      case RuntimeMode.unsupported:
        return 'Não suportado';
    }
  }
}

/// Production profile defaults for agent action path policies.
abstract final class AgentActionPathProdDefaultsConstants {
  static const Set<String> productionProfileNames = {'prod', 'production'};

  static const String productionAllowlistRequiredUserMessage =
      'No perfil de producao, configure diretorios de trabalho permitidos antes de salvar ou executar acoes de linha de comando, executavel ou script.';

  static bool isProductionProfile(String? profile) {
    final normalized = profile?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }

    return productionProfileNames.contains(normalized);
  }
}

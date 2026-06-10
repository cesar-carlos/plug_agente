/// Resolves the agent operational profile used by action environment policy.
abstract interface class IAgentOperationalProfileResolver {
  String? get currentProfile;

  bool get isProductionProfile;
}

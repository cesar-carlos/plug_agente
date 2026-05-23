part of '../agent_actions_provider.dart';

List<AgentActionDefinition> filteredDefinitionsFor(AgentActionsProvider provider) {
  final cached = provider._filteredDefinitionsCache;
  if (cached != null) {
    return cached;
  }

  final matched = provider._definitions
      .where(
        (AgentActionDefinition definition) => agentActionsMatchesDefinitionListFilter(
          definition: definition,
          typeFilter: provider._definitionTypeFilter,
          stateFilter: provider._definitionStateFilter,
          searchQuery: provider._definitionSearchQuery,
        ),
      )
      .toList(growable: false);
  final selectedId = provider.selectedActionId;
  if (selectedId == null) {
    return provider._filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
  }
  if (matched.any((definition) => definition.id == selectedId)) {
    return provider._filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
  }
  final selected = provider._existingDefinition(selectedId);
  if (selected == null) {
    return provider._filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(matched);
  }
  return provider._filteredDefinitionsCache = List<AgentActionDefinition>.unmodifiable(<AgentActionDefinition>[
    selected,
    ...matched,
  ]);
}

bool hasDefinitionListFiltersFor(AgentActionsProvider provider) =>
    provider._definitionTypeFilter != null ||
    provider._definitionStateFilter != null ||
    provider._definitionSearchQuery.isNotEmpty;

void setDefinitionTypeFilterFor(AgentActionsProvider provider, AgentActionType? type) {
  if (provider._definitionTypeFilter == type) {
    return;
  }

  provider._definitionTypeFilter = type;
  provider.notifyListeners();
}

void setDefinitionStateFilterFor(AgentActionsProvider provider, AgentActionState? state) {
  if (provider._definitionStateFilter == state) {
    return;
  }

  provider._definitionStateFilter = state;
  provider.notifyListeners();
}

void setDefinitionSearchQueryFor(AgentActionsProvider provider, String query) {
  final normalized = query.trim();
  if (provider._definitionSearchQuery == normalized) {
    return;
  }

  provider._definitionSearchQuery = normalized;
  provider.notifyListeners();
}

void clearDefinitionFiltersFor(AgentActionsProvider provider) {
  if (!hasDefinitionListFiltersFor(provider)) {
    return;
  }

  provider._definitionTypeFilter = null;
  provider._definitionStateFilter = null;
  provider._definitionSearchQuery = '';
  provider.notifyListeners();
}

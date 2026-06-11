import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_list_preferences.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_file_service.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';

/// Keys for localized form validation messages resolved by the section widget.
enum ClientTokenFormErrorKey {
  globalPermissionRequired,
  ruleOrGlobalPermissionsRequired,
  payloadInvalidJson,
  payloadMustBeJsonObject,
  payloadDatabaseMustBeString,
  payloadDatabaseCannotBeEmpty,
}

/// Owns client-token section form state, list filters, and draft assembly.
///
/// Extracted from the client token section widget so layout, dialogs and
/// provider orchestration while form/list logic stays injectable and testable.
class ClientTokenSectionController {
  ClientTokenSectionController({
    required IAppSettingsStore? Function() settingsStoreLookup,
    required VoidCallback onSectionChanged,
    ClientTokenRuleFileService ruleFileService = const ClientTokenRuleFileService(),
  }) : _listPreferences = ClientTokenListPreferences(settingsStoreLookup),
       _ruleFileService = ruleFileService,
       _onSectionChanged = onSectionChanged;

  final ClientTokenListPreferences _listPreferences;
  final ClientTokenRuleFileService _ruleFileService;
  final VoidCallback _onSectionChanged;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController clientIdController = TextEditingController();
  final TextEditingController agentIdController = TextEditingController();
  final TextEditingController payloadController = TextEditingController();
  final TextEditingController listClientFilterController = TextEditingController();
  final List<ClientTokenRuleDraft> rules = <ClientTokenRuleDraft>[];
  final ValueNotifier<int> createTokenDialogRevision = ValueNotifier<int>(0);
  final FocusNode createTokenDialogAgentFocusNode = FocusNode();

  Timer? _clientFilterDebounceTimer;
  var _isCreateTokenDialogOpen = false;
  var _dialogControllerListenersAttached = false;

  bool allTables = false;
  bool allViews = false;
  bool globalCanRead = false;
  bool globalCanUpdate = false;
  bool globalCanDelete = false;
  bool globalCanDdl = false;
  ClientTokenStatusFilter tokenStatusFilter = ClientTokenStatusFilter.all;
  ClientTokenSortOption tokenSortOption = ClientTokenSortOption.newest;
  bool autoRefreshAfterCreate = true;
  ClientTokenFormErrorKey? formErrorKey;
  String? editingTokenId;
  int? editingTokenVersion;
  ClientTokenSummary? editingTokenSnapshot;
  bool isImportingRules = false;

  bool get isGlobalScopeMode => allTables || allViews;

  void dispose() {
    nameController.dispose();
    clientIdController.dispose();
    agentIdController.dispose();
    payloadController.dispose();
    listClientFilterController.dispose();
    _clientFilterDebounceTimer?.cancel();
    createTokenDialogRevision.dispose();
    createTokenDialogAgentFocusNode.dispose();
  }

  void notifyCreateTokenDialogChanged() {
    if (_isCreateTokenDialogOpen) {
      createTokenDialogRevision.value++;
      return;
    }
    _onSectionChanged();
  }

  void markCreateTokenDialogOpen(bool open) {
    _isCreateTokenDialogOpen = open;
  }

  void attachDialogControllerListeners() {
    if (_dialogControllerListenersAttached) {
      return;
    }
    nameController.addListener(notifyCreateTokenDialogChanged);
    clientIdController.addListener(notifyCreateTokenDialogChanged);
    agentIdController.addListener(notifyCreateTokenDialogChanged);
    payloadController.addListener(notifyCreateTokenDialogChanged);
    _dialogControllerListenersAttached = true;
  }

  void detachDialogControllerListeners() {
    if (!_dialogControllerListenersAttached) {
      return;
    }
    nameController.removeListener(notifyCreateTokenDialogChanged);
    clientIdController.removeListener(notifyCreateTokenDialogChanged);
    agentIdController.removeListener(notifyCreateTokenDialogChanged);
    payloadController.removeListener(notifyCreateTokenDialogChanged);
    _dialogControllerListenersAttached = false;
  }

  ClientTokenListPreferencesData? restoreListPreferences() => _listPreferences.restore();

  void applyRestoredListPreferences(ClientTokenListPreferencesData data) {
    listClientFilterController.text = data.clientFilter;
    tokenStatusFilter = data.statusFilter;
    tokenSortOption = data.sortOption;
    autoRefreshAfterCreate = data.autoRefreshAfterCreate;
  }

  Future<void> saveListPreferences() {
    return _listPreferences.save((
      clientFilter: listClientFilterController.text.trim(),
      statusFilter: tokenStatusFilter,
      sortOption: tokenSortOption,
      autoRefreshAfterCreate: autoRefreshAfterCreate,
    ));
  }

  ClientTokenCreateRequest? tryBuildDraftRequestFromForm() {
    final (:payload, :error) = parseClientTokenPayloadJson(payloadController.text);
    if (error != null || payload == null) {
      return null;
    }
    return ClientTokenCreateRequest(
      clientId: clientIdController.text.trim(),
      name: nameController.text.trim(),
      agentId: agentIdController.text.trim().isEmpty ? null : agentIdController.text.trim(),
      payload: payload,
      allTables: allTables,
      allViews: allViews,
      globalPermissions: buildGlobalPermissions(),
      rules: isGlobalScopeMode ? const <ClientTokenRule>[] : buildRules(),
    );
  }

  bool hasFormChanges() {
    final snapshot = editingTokenSnapshot;
    if (snapshot == null) {
      return true;
    }
    final draft = tryBuildDraftRequestFromForm();
    if (draft == null) {
      return true;
    }
    return draft.changesAuthorizationPolicyFrom(snapshot) || draft.changesMetadataFrom(snapshot);
  }

  bool hasPolicyChanges() {
    final snapshot = editingTokenSnapshot;
    if (snapshot == null) {
      return false;
    }
    final draft = tryBuildDraftRequestFromForm();
    if (draft == null) {
      return false;
    }
    return draft.changesAuthorizationPolicyFrom(snapshot);
  }

  void mergeRules(List<ClientTokenRuleDraft> incoming) {
    final seen = <String>{};
    final deduped = incoming.reversed
        .where((d) => seen.add('${d.resource.toLowerCase()}:${d.resourceType.name}'))
        .toList()
        .reversed
        .toList();

    for (final draft in deduped) {
      final existingIndex = rules.indexWhere(
        (r) => r.resource.toLowerCase() == draft.resource.toLowerCase() && r.resourceType == draft.resourceType,
      );
      if (existingIndex >= 0) {
        rules[existingIndex] = draft;
      } else {
        rules.add(draft);
      }
    }
  }

  void removeRule(int index) {
    rules.removeAt(index);
    notifyCreateTokenDialogChanged();
  }

  void setImportingRules(bool value) {
    isImportingRules = value;
    notifyCreateTokenDialogChanged();
  }

  Future<FilePickerResult?> pickRulesImportFile() {
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
  }

  Future<ClientTokenRuleImportOutcome> importRulesFromPath(String filePath) {
    return _ruleFileService.importFromFile(filePath);
  }

  Future<String?> pickRulesExportPath(String defaultFileName) {
    return FilePicker.platform.saveFile(
      dialogTitle: defaultFileName,
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
  }

  Future<void> exportRulesToPath(String savePath) {
    return _ruleFileService.exportToFile(savePath, rules);
  }

  void loadTokenIntoForm(ClientTokenSummary? baseToken) {
    formErrorKey = null;
    editingTokenId = baseToken?.id;
    editingTokenVersion = baseToken?.version;
    editingTokenSnapshot = baseToken;
    nameController.text = baseToken?.name ?? '';
    clientIdController.text = baseToken?.clientId ?? generateClientId();
    agentIdController.text = baseToken?.agentId ?? '';
    payloadController.text = baseToken?.payload.isEmpty ?? true ? '' : jsonEncode(baseToken!.payload);
    rules
      ..clear()
      ..addAll(
        baseToken?.rules
                .map(
                  (rule) => ClientTokenRuleDraft(
                    resource: rule.resource.name,
                    resourceType: rule.resource.resourceType,
                    effect: rule.effect,
                    canRead: rule.permissions.canRead,
                    canUpdate: rule.permissions.canUpdate,
                    canDelete: rule.permissions.canDelete,
                    canDdl: rule.permissions.canDdl,
                  ),
                )
                .toList() ??
            <ClientTokenRuleDraft>[],
      );
    allTables = baseToken?.allTables ?? false;
    allViews = baseToken?.allViews ?? false;
    globalCanRead = baseToken?.globalPermissions.canRead ?? false;
    globalCanUpdate = baseToken?.globalPermissions.canUpdate ?? false;
    globalCanDelete = baseToken?.globalPermissions.canDelete ?? false;
    globalCanDdl = baseToken?.globalPermissions.canDdl ?? false;
  }

  void clearFormError() {
    formErrorKey = null;
  }

  ClientTokenCreateRequest? buildSubmitRequest() {
    formErrorKey = null;

    final payloadResult = parsePayloadForSubmit();
    if (payloadResult == null) {
      return null;
    }

    final globalPermissions = buildGlobalPermissions();
    final builtRules = buildRules();
    if (isGlobalScopeMode && !globalPermissions.hasAnyPermission) {
      formErrorKey = ClientTokenFormErrorKey.globalPermissionRequired;
      notifyCreateTokenDialogChanged();
      return null;
    }
    if (!isGlobalScopeMode && builtRules.isEmpty) {
      formErrorKey = ClientTokenFormErrorKey.ruleOrGlobalPermissionsRequired;
      notifyCreateTokenDialogChanged();
      return null;
    }

    return ClientTokenCreateRequest(
      clientId: clientIdController.text.trim(),
      name: nameController.text.trim(),
      agentId: agentIdController.text.trim().isEmpty ? null : agentIdController.text.trim(),
      payload: payloadResult,
      allTables: allTables,
      allViews: allViews,
      globalPermissions: globalPermissions,
      rules: isGlobalScopeMode ? const <ClientTokenRule>[] : builtRules,
    );
  }

  void clearTokenDraftForm() {
    editingTokenId = null;
    editingTokenVersion = null;
    editingTokenSnapshot = null;
    clientIdController.text = generateClientId();
    agentIdController.clear();
    payloadController.clear();
    rules.clear();
    allTables = false;
    allViews = false;
    globalCanRead = false;
    globalCanUpdate = false;
    globalCanDelete = false;
    globalCanDdl = false;
  }

  Map<String, dynamic>? parsePayloadForSubmit() {
    final (:payload, :error) = parseClientTokenPayloadJson(payloadController.text);
    if (error == null) {
      final payloadValidationError = validateClientTokenPayload(payload!);
      if (payloadValidationError == null) {
        return payload;
      }
      formErrorKey = switch (payloadValidationError) {
        ClientTokenPayloadValidationError.databaseMustBeString =>
          ClientTokenFormErrorKey.payloadDatabaseMustBeString,
        ClientTokenPayloadValidationError.databaseCannotBeEmpty =>
          ClientTokenFormErrorKey.payloadDatabaseCannotBeEmpty,
      };
      notifyCreateTokenDialogChanged();
      return null;
    }
    formErrorKey = switch (error) {
      ClientTokenPayloadParseError.invalidJson => ClientTokenFormErrorKey.payloadInvalidJson,
      ClientTokenPayloadParseError.notAnObject => ClientTokenFormErrorKey.payloadMustBeJsonObject,
    };
    notifyCreateTokenDialogChanged();
    return null;
  }

  ClientPermissionSet buildGlobalPermissions() {
    if (!isGlobalScopeMode) {
      return ClientPermissionSet.none;
    }

    return ClientPermissionSet(
      canRead: globalCanRead,
      canUpdate: globalCanUpdate,
      canDelete: globalCanDelete,
      canDdl: globalCanDdl,
    );
  }

  String generateClientId() {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return 'client_$timestamp';
  }

  List<ClientTokenRule> buildRules() {
    final built = <ClientTokenRule>[];
    for (final draft in rules) {
      if (!draft.hasAnyPermission) {
        continue;
      }
      built.add(
        ClientTokenRule(
          resource: DatabaseResource(
            resourceType: draft.resourceType,
            name: draft.resource,
          ),
          permissions: ClientPermissionSet(
            canRead: draft.canRead,
            canUpdate: draft.canUpdate,
            canDelete: draft.canDelete,
            canDdl: draft.canDdl,
          ),
          effect: draft.effect,
        ),
      );
    }
    return built;
  }

  void clearTokenFilters() {
    listClientFilterController.clear();
    tokenStatusFilter = ClientTokenStatusFilter.all;
    tokenSortOption = ClientTokenSortOption.newest;
    _onSectionChanged();
  }

  ClientTokenListQuery buildListQuery() {
    return ClientTokenListQuery(
      clientIdContains: listClientFilterController.text.trim(),
      status: tokenStatusFilter,
      sort: tokenSortOption,
    );
  }

  bool hasActiveFilters() {
    return listClientFilterController.text.trim().isNotEmpty ||
        tokenStatusFilter != ClientTokenStatusFilter.all ||
        tokenSortOption != ClientTokenSortOption.newest;
  }

  void handleClientFilterChanged(VoidCallback onDebounced) {
    _clientFilterDebounceTimer?.cancel();
    _clientFilterDebounceTimer = Timer(
      AppConstants.clientTokenDebounceDelay,
      onDebounced,
    );
  }

  void updateTokenStatusFilter(ClientTokenStatusFilter value) {
    tokenStatusFilter = value;
    _onSectionChanged();
  }

  void updateTokenSortOption(ClientTokenSortOption value) {
    tokenSortOption = value;
    _onSectionChanged();
  }

  void toggleAutoRefreshAfterCreate() {
    autoRefreshAfterCreate = !autoRefreshAfterCreate;
    _onSectionChanged();
  }
}

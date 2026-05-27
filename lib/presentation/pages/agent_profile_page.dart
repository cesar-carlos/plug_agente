import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cep.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cnpj.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/mappers/agent_profile_validation_messages_l10n.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_form_controller.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_outcome.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_address_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_contact_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_identity_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_notes_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_save_action.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class AgentProfilePage extends StatefulWidget {
  const AgentProfilePage({
    this.configId,
    this.lookupAgentCnpj,
    this.lookupAgentCep,
    this.pushAgentProfileToHub,
    super.key,
  });

  final String? configId;
  final LookupAgentCnpj? lookupAgentCnpj;
  final LookupAgentCep? lookupAgentCep;
  final PushAgentProfileToHub? pushAgentProfileToHub;

  @override
  State<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends State<AgentProfilePage> {
  late final AgentProfileFormController _formController;
  late final LookupAgentCnpj _lookupAgentCnpj;
  late final LookupAgentCep _lookupAgentCep;
  late final PushAgentProfileToHub _pushAgentProfileToHub;

  final ValueNotifier<bool> _isLookingUpCnpj = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLookingUpCep = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSaving = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isFormReady = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canSave = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canLookup = ValueNotifier<bool>(true);
  late final VoidCallback _refreshDerivedState;

  AgentProfileSaveCoordinator? _saveCoordinator;
  ConfigProvider? _configProvider;

  @override
  void initState() {
    super.initState();
    _formController = AgentProfileFormController();
    _lookupAgentCnpj = widget.lookupAgentCnpj ?? getIt<LookupAgentCnpj>();
    _lookupAgentCep = widget.lookupAgentCep ?? getIt<LookupAgentCep>();
    _pushAgentProfileToHub = widget.pushAgentProfileToHub ?? getIt<PushAgentProfileToHub>();

    _refreshDerivedState = () {
      final saving = _isSaving.value;
      final cnpjBusy = _isLookingUpCnpj.value;
      final cepBusy = _isLookingUpCep.value;
      _canLookup.value = !saving;
      _canSave.value = _isFormReady.value && !saving && !cnpjBusy && !cepBusy;
    };
    _isSaving.addListener(_refreshDerivedState);
    _isLookingUpCnpj.addListener(_refreshDerivedState);
    _isLookingUpCep.addListener(_refreshDerivedState);
    _isFormReady.addListener(_refreshDerivedState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setupConfigListener();
      unawaited(_initializePage());
    });
  }

  @override
  void didUpdateWidget(covariant AgentProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configId != widget.configId) {
      _formController.resetForConfig();
      _isFormReady.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_initializePage());
      });
    }
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigStateChanged);
    _isSaving.removeListener(_refreshDerivedState);
    _isLookingUpCnpj.removeListener(_refreshDerivedState);
    _isLookingUpCep.removeListener(_refreshDerivedState);
    _isFormReady.removeListener(_refreshDerivedState);
    _isLookingUpCnpj.dispose();
    _isLookingUpCep.dispose();
    _isSaving.dispose();
    _isFormReady.dispose();
    _canSave.dispose();
    _canLookup.dispose();
    _formController.dispose();
    super.dispose();
  }

  void _setupConfigListener() {
    _configProvider = context.read<ConfigProvider>()..addListener(_onConfigStateChanged);
    _refreshFormReadyState(_configProvider);
  }

  void _onConfigStateChanged() {
    _initializeFormIfReady(provider: _configProvider);
    _refreshFormReadyState(_configProvider);
  }

  Future<void> _initializePage() async {
    if (!mounted) {
      return;
    }
    final configId = widget.configId;
    if (configId != null) {
      await context.read<ConfigProvider>().loadConfigById(configId);
      if (!mounted) {
        return;
      }
    }
    _initializeFormIfReady();
    _refreshFormReadyState(_configProvider);
  }

  void _initializeFormIfReady({ConfigProvider? provider}) {
    if (!mounted) {
      return;
    }
    final source = provider ?? context.read<ConfigProvider>();
    if (!_formController.fieldsInitialized && !source.isLoading && source.currentConfig != null) {
      _formController.initializeFromConfig(source.currentConfig);
    }
  }

  void _refreshFormReadyState(ConfigProvider? provider) {
    final source = provider;
    if (source == null) {
      _isFormReady.value = false;
      return;
    }
    _isFormReady.value = !source.isLoading && source.currentConfig != null;
  }

  Future<void> _lookupCnpj() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }

    _clearProviderError();
    _isLookingUpCnpj.value = true;
    try {
      final result = await _lookupAgentCnpj(
        rawDocument: _formController.documentController.text,
        invalidLengthMessage: l10n.agentProfileLookupCnpjInvalid,
      );

      if (!mounted) {
        return;
      }

      if (result.isError()) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: result.exceptionOrNull()!.toDisplayMessage(),
        );
        return;
      }

      _formController.applyOpenCnpjData(result.getOrThrow());
    } catch (error, stackTrace) {
      AppLogger.error('CNPJ lookup failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isLookingUpCnpj.value = false;
      }
    }
  }

  Future<void> _lookupCep() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }

    _clearProviderError();
    _isLookingUpCep.value = true;
    try {
      final result = await _lookupAgentCep(
        rawPostalCode: _formController.postalCodeController.text,
        invalidLengthMessage: l10n.agentProfileLookupCepInvalid,
      );

      if (!mounted) {
        return;
      }

      if (result.isError()) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleError,
          message: result.exceptionOrNull()!.toDisplayMessage(),
        );
        return;
      }

      _formController.applyViaCepData(result.getOrThrow());
    } catch (error, stackTrace) {
      AppLogger.error('CEP lookup failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isLookingUpCep.value = false;
      }
    }
  }

  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }

    final parseResult = AgentProfile.fromFormFields(
      name: _formController.nameController.text,
      tradeName: _formController.tradeNameController.text,
      document: _formController.documentController.text,
      phone: _formController.phoneController.text,
      mobile: _formController.mobileController.text,
      email: _formController.emailController.text,
      street: _formController.streetController.text,
      number: _formController.addressNumberController.text,
      district: _formController.districtController.text,
      postalCode: _formController.postalCodeController.text,
      city: _formController.cityController.text,
      state: _formController.stateController.text,
      notes: _formController.notesController.text,
      validationMessages: agentProfileValidationMessages(l10n),
    );

    if (parseResult.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: parseResult.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    final profile = parseResult.getOrThrow();
    _formController.applyValidatedProfile(profile);

    _clearProviderError();
    _isSaving.value = true;
    AgentProfileSaveOutcome? outcome;
    try {
      outcome = await _resolveSaveCoordinator().save(profile);
    } catch (error, stackTrace) {
      AppLogger.error('Agent profile save failed unexpectedly', '$error\n$stackTrace');
      rethrow;
    } finally {
      if (mounted) {
        _isSaving.value = false;
      }
    }

    if (!mounted) {
      return;
    }

    await _showSaveFeedback(l10n, outcome);
  }

  AgentProfileSaveCoordinator _resolveSaveCoordinator() {
    return _saveCoordinator ??= AgentProfileSaveCoordinator(
      configProvider: context.read<ConfigProvider>(),
      authProvider: context.read<AuthProvider>(),
      pushAgentProfileToHub: _pushAgentProfileToHub,
      registerProfileProvider: getIt<AgentRegisterProfileProvider>(),
    );
  }

  Future<void> _showSaveFeedback(
    AppLocalizations l10n,
    AgentProfileSaveOutcome outcome,
  ) async {
    switch (outcome) {
      case AgentProfileSaveLocalFailure(errorMessage: final message):
        await SettingsFeedback.showError(
          context: context,
          title: l10n.modalTitleErrorSaving,
          message: message,
        );
      case AgentProfileSaveHubPartialFailure(hubErrorMessage: final detail):
        await SettingsFeedback.showError(
          context: context,
          title: l10n.agentProfileHubSavePartialTitle,
          message: l10n.agentProfileHubSavePartialMessage(detail),
        );
      case AgentProfileSaveSynced():
        await SettingsFeedback.showSuccess(
          context: context,
          title: l10n.modalTitleSuccess,
          message: l10n.agentProfileSaveSuccessSynced,
        );
      case AgentProfileSaveLocalOnly():
        await SettingsFeedback.showSuccess(
          context: context,
          title: l10n.modalTitleSuccess,
          message: l10n.agentProfileSaveSuccessLocal,
        );
    }
  }

  void _clearProviderError() {
    final provider = _configProvider ?? context.read<ConfigProvider>();
    if (provider.error.isNotEmpty) {
      provider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewModel = context.select<ConfigProvider, _ConfigViewModel>(
      (provider) => _ConfigViewModel(
        isLoading: provider.isLoading,
        error: provider.error,
      ),
    );
    final isInitialLoading = viewModel.isLoading && !_formController.fieldsInitialized;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navAgentProfile,
          style: context.sectionTitle,
        ),
        commandBar: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: AgentProfileSaveAction(
            isSaving: _isSaving,
            canSave: _canSave,
            saveLabel: l10n.agentProfileActionSave,
            onPressed: _saveProfile,
          ),
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: isInitialLoading
              ? _AgentProfileLoading(message: l10n.agentProfileLoading)
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppLayout.maxWideFormWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (viewModel.error.isNotEmpty) ...[
                            InfoBar(
                              title: Text(l10n.modalTitleError),
                              content: Text(viewModel.error),
                              severity: InfoBarSeverity.error,
                              isLong: true,
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          SettingsSectionBlock(
                            title: l10n.agentProfileFormSectionTitle,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppCard(
                                  child: AgentProfileIdentitySection(
                                    controller: _formController,
                                    l10n: l10n,
                                    isLookingUpCnpj: _isLookingUpCnpj,
                                    canLookup: _canLookup,
                                    onLookupCnpj: () => unawaited(_lookupCnpj()),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AgentProfileContactSection(
                                  controller: _formController,
                                  l10n: l10n,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AgentProfileAddressSection(
                                  controller: _formController,
                                  l10n: l10n,
                                  isLookingUpCep: _isLookingUpCep,
                                  canLookup: _canLookup,
                                  onLookupCep: () => unawaited(_lookupCep()),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AgentProfileNotesSection(
                                  controller: _formController,
                                  l10n: l10n,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: AgentProfileSaveAction(
                                    isSaving: _isSaving,
                                    canSave: _canSave,
                                    saveLabel: l10n.agentProfileActionSave,
                                    onPressed: _saveProfile,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

@immutable
class _ConfigViewModel {
  const _ConfigViewModel({
    required this.isLoading,
    required this.error,
  });

  final bool isLoading;
  final String error;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ConfigViewModel && other.isLoading == isLoading && other.error == error;
  }

  @override
  int get hashCode => Object.hash(isLoading, error);
}

class _AgentProfileLoading extends StatelessWidget {
  const _AgentProfileLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ProgressRing(),
          const SizedBox(height: AppSpacing.md),
          Text(message),
        ],
      ),
    );
  }
}

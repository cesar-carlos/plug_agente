import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/mappers/agent_profile_validation_messages_l10n.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form_components.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class AgentProfilePage extends StatefulWidget {
  const AgentProfilePage({
    this.configId,
    this.openCnpjClient,
    this.viaCepClient,
    this.pushAgentProfileToHub,
    super.key,
  });

  final String? configId;
  final OpenCnpjClient? openCnpjClient;
  final ViaCepClient? viaCepClient;
  final PushAgentProfileToHub? pushAgentProfileToHub;

  @override
  State<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends State<AgentProfilePage> {
  static final RegExp _nonDigitsPattern = RegExp('[^0-9]');

  PushAgentProfileToHub get _pushToHub => widget.pushAgentProfileToHub ?? getIt<PushAgentProfileToHub>();

  late final ConfigFormController _formController;
  late final OpenCnpjClient _openCnpjClient;
  late final ViaCepClient _viaCepClient;
  bool _isLookingUpCnpj = false;
  bool _isLookingUpCep = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _formController = ConfigFormController();
    _openCnpjClient = widget.openCnpjClient ?? getIt<OpenCnpjClient>();
    _viaCepClient = widget.viaCepClient ?? getIt<ViaCepClient>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.configId != null) {
        await _loadConfig(widget.configId!);
      }
      _checkAndInitializeFields();
    });
  }

  Future<void> _loadConfig(String configId) async {
    final configProvider = context.read<ConfigProvider>();
    await configProvider.loadConfigById(configId);
  }

  void _checkAndInitializeFields() {
    if (!mounted) {
      return;
    }

    final configProvider = context.read<ConfigProvider>();
    if (!_formController.fieldsInitialized && !configProvider.isLoading && configProvider.currentConfig != null) {
      _formController.initializeFromConfig(configProvider.currentConfig);
      return;
    }

    if (configProvider.isLoading) {
      unawaited(
        Future<void>.delayed(
          AppConstants.formTransitionDelay,
          _checkAndInitializeFields,
        ),
      );
    }
  }

  @override
  void dispose() {
    _formController.dispose();
    super.dispose();
  }

  Future<void> _lookupCnpj() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }
    final digits = _digitsOnly(_formController.cnaeCnpjCpfController.text);
    if (digits.length != 14) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: l10n.agentProfileLookupCnpjInvalid,
      );
      return;
    }

    setState(() {
      _isLookingUpCnpj = true;
    });

    final result = await _openCnpjClient.lookupCnpj(digits);

    if (!mounted) {
      return;
    }

    setState(() {
      _isLookingUpCnpj = false;
    });

    if (result.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: result.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    _applyOpenCnpjData(result.getOrThrow());
  }

  Future<void> _lookupCep() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }
    final digits = _digitsOnly(_formController.cepController.text);
    if (digits.length != 8) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: l10n.agentProfileLookupCepInvalid,
      );
      return;
    }

    setState(() {
      _isLookingUpCep = true;
    });

    final result = await _viaCepClient.lookupCep(digits);

    if (!mounted) {
      return;
    }

    setState(() {
      _isLookingUpCep = false;
    });

    if (result.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: result.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    _applyViaCepData(result.getOrThrow());
  }

  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return;
    }
    final result = AgentProfile.fromFormFields(
      name: _formController.nomeController.text,
      tradeName: _formController.nomeFantasiaController.text,
      document: _formController.cnaeCnpjCpfController.text,
      phone: _formController.telefoneController.text,
      mobile: _formController.celularController.text,
      email: _formController.emailController.text,
      street: _formController.enderecoController.text,
      number: _formController.numeroEnderecoController.text,
      district: _formController.bairroController.text,
      postalCode: _formController.cepController.text,
      city: _formController.nomeMunicipioController.text,
      state: _formController.ufMunicipioController.text,
      notes: _formController.observacaoController.text,
      validationMessages: agentProfileValidationMessages(l10n),
    );

    if (result.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: result.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    final profile = result.getOrThrow();
    _applyValidatedProfile(profile);

    setState(() {
      _isSaving = true;
    });

    final configProvider = context.read<ConfigProvider>();
    configProvider.updateAgentProfile(profile);
    final saveResult = await configProvider.saveConfig();

    if (!mounted) {
      return;
    }

    if (saveResult.isError()) {
      setState(() {
        _isSaving = false;
      });
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleErrorSaving,
        message: saveResult.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    var hubSyncFailed = false;
    String? hubSyncErrorMessage;
    var hubSyncSucceeded = false;
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final savedConfig = configProvider.currentConfig;
    final authHeaderToken = authProvider.currentToken?.token.trim();
    final configStoredToken = savedConfig?.authToken?.trim();
    final accessToken = (authHeaderToken != null && authHeaderToken.isNotEmpty)
        ? authHeaderToken
        : (configStoredToken ?? '');
    if (connectionProvider.isConnected &&
        accessToken.isNotEmpty &&
        savedConfig != null &&
        savedConfig.serverUrl.trim().isNotEmpty &&
        savedConfig.agentId.trim().isNotEmpty) {
      final pushResult = await _pushToHub(
        serverUrl: savedConfig.serverUrl,
        agentId: savedConfig.agentId,
        accessToken: accessToken,
        profile: profile,
        expectedProfileVersion: savedConfig.hubProfileVersion,
      );
      if (!mounted) {
        return;
      }
      if (pushResult.isSuccess()) {
        final synced = pushResult.getOrThrow();
        hubSyncSucceeded = true;
        final persistResult = await configProvider.persistHubProfileCatalogSync(
          profileVersion: synced.profileVersion,
          profileUpdatedAtIso: synced.profileUpdatedAt,
        );
        persistResult.fold(
          (_) {},
          (Object failure) {
            AppLogger.warning(
              'Hub profile synced but failed to persist catalog version locally: '
              '${failure.toDisplayMessage()}',
            );
          },
        );
      } else {
        hubSyncFailed = true;
        hubSyncErrorMessage = pushResult.exceptionOrNull()!.toDisplayMessage();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    if (!mounted) {
      return;
    }

    final l10nSuccess = AppLocalizations.of(context);
    if (l10nSuccess == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (hubSyncFailed) {
      final hubErrorDetail = hubSyncErrorMessage ?? '';
      await SettingsFeedback.showError(
        context: context,
        title: l10nSuccess.agentProfileHubSavePartialTitle,
        message: l10nSuccess.agentProfileHubSavePartialMessage(hubErrorDetail),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await SettingsFeedback.showSuccess(
      context: context,
      title: l10nSuccess.modalTitleSuccess,
      message: hubSyncSucceeded ? l10nSuccess.agentProfileSaveSuccessSynced : l10nSuccess.agentProfileSaveSuccessLocal,
    );
  }

  void _applyOpenCnpjData(OpenCnpjCompanyData data) {
    BrazilianFieldFormatters.apply(
      _formController.cnaeCnpjCpfController,
      data.cnpj,
      BrazilianFieldFormatters.document,
    );
    _setText(_formController.nomeController, data.legalName);
    _setOptionalText(_formController.nomeFantasiaController, data.tradeName);
    _setOptionalText(_formController.emailController, data.email);
    _setOptionalFormatted(
      _formController.telefoneController,
      data.phone,
      BrazilianFieldFormatters.phone,
    );
    _setOptionalFormatted(
      _formController.celularController,
      data.mobile,
      BrazilianFieldFormatters.phone,
    );
    _setOptionalText(_formController.enderecoController, data.street);
    _setOptionalText(_formController.numeroEnderecoController, data.number);
    _setOptionalText(_formController.bairroController, data.district);
    _setOptionalFormatted(
      _formController.cepController,
      data.postalCode,
      BrazilianFieldFormatters.postalCode,
    );
    _setOptionalText(_formController.nomeMunicipioController, data.city);
    _setOptionalFormatted(
      _formController.ufMunicipioController,
      data.state,
      BrazilianFieldFormatters.state,
    );
  }

  void _applyViaCepData(ViaCepAddress data) {
    BrazilianFieldFormatters.apply(
      _formController.cepController,
      data.cep,
      BrazilianFieldFormatters.postalCode,
    );
    _setText(_formController.enderecoController, data.logradouro);
    _setText(_formController.bairroController, data.bairro);
    _setText(_formController.nomeMunicipioController, data.localidade);
    BrazilianFieldFormatters.apply(
      _formController.ufMunicipioController,
      data.uf,
      BrazilianFieldFormatters.state,
    );
  }

  void _applyValidatedProfile(AgentProfile profile) {
    _setText(_formController.nomeController, profile.name);
    _setText(_formController.nomeFantasiaController, profile.tradeName);
    BrazilianFieldFormatters.apply(
      _formController.cnaeCnpjCpfController,
      profile.document,
      BrazilianFieldFormatters.document,
    );

    if (profile.phone != null && profile.phone!.isNotEmpty) {
      BrazilianFieldFormatters.apply(
        _formController.telefoneController,
        profile.phone!,
        BrazilianFieldFormatters.phone,
      );
    } else {
      _formController.telefoneController.clear();
    }

    BrazilianFieldFormatters.apply(
      _formController.celularController,
      profile.mobile,
      BrazilianFieldFormatters.phone,
    );
    _setText(_formController.emailController, profile.email);
    _setText(_formController.enderecoController, profile.address.street);
    _setText(_formController.numeroEnderecoController, profile.address.number);
    _setText(_formController.bairroController, profile.address.district);
    BrazilianFieldFormatters.apply(
      _formController.cepController,
      profile.address.postalCode,
      BrazilianFieldFormatters.postalCode,
    );
    _setText(_formController.nomeMunicipioController, profile.address.city);
    BrazilianFieldFormatters.apply(
      _formController.ufMunicipioController,
      profile.address.state,
      BrazilianFieldFormatters.state,
    );
    _formController.observacaoController.text = profile.notes ?? '';
  }

  void _setText(TextEditingController controller, String value) {
    controller.text = value.trim();
  }

  void _setOptionalText(TextEditingController controller, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    controller.text = trimmed;
  }

  void _setOptionalFormatted(
    TextEditingController controller,
    String? value,
    List<TextInputFormatter> formatters,
  ) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    BrazilianFieldFormatters.apply(controller, trimmed, formatters);
  }

  String _digitsOnly(String value) {
    return value.replaceAll(_nonDigitsPattern, '');
  }

  String? _requiredValidator(AppLocalizations l10n, String label, String? value) {
    if ((value?.trim() ?? '').isEmpty) {
      return l10n.formFieldRequired(label);
    }
    return null;
  }

  String? _requiredWithSpec(
    AppLocalizations l10n,
    String label,
    FieldSpec fieldSpec,
    String? value,
  ) {
    final requiredError = _requiredValidator(l10n, label, value);
    if (requiredError != null) {
      return requiredError;
    }
    return fieldSpec.validator?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.watch<ConfigProvider>();
    final isInitialLoading = configProvider.isLoading && !_formController.fieldsInitialized;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navAgentProfile,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: isInitialLoading
              ? _AgentProfileLoading(message: l10n.agentProfileLoading)
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: AppLayout.scrollbarPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.maxWideFormWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (configProvider.error.isNotEmpty) ...[
                            InfoBar(
                              title: Text(l10n.modalTitleError),
                              content: Text(configProvider.error),
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
                                  child: _AgentProfileSection(
                                    title: l10n.agentProfileSectionIdentity,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _ResponsiveFieldRow(
                                          children: [
                                            AppTextField(
                                              label: l10n.agentProfileFieldName,
                                              controller: _formController.nomeController,
                                              validator: (value) => _requiredValidator(
                                                l10n,
                                                l10n.agentProfileFieldName,
                                                value,
                                              ),
                                            ),
                                            AppTextField(
                                              label: l10n.agentProfileFieldTradeName,
                                              controller: _formController.nomeFantasiaController,
                                              validator: (value) => _requiredValidator(
                                                l10n,
                                                l10n.agentProfileFieldTradeName,
                                                value,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        _ResponsiveFieldActionRow(
                                          field: AppTextField(
                                            label: l10n.agentProfileFieldDocument,
                                            controller: _formController.cnaeCnpjCpfController,
                                            fieldSpec: AppFieldSpecs.document(l10n),
                                            validator: (value) => _requiredWithSpec(
                                              l10n,
                                              l10n.agentProfileFieldDocument,
                                              AppFieldSpecs.document(l10n),
                                              value,
                                            ),
                                          ),
                                          action: AppButton(
                                            label: l10n.agentProfileActionLookupCnpj,
                                            isPrimary: false,
                                            isLoading: _isLookingUpCnpj,
                                            onPressed: () {
                                              unawaited(_lookupCnpj());
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _AgentProfileSection(
                                  title: l10n.agentProfileSectionContact,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _ResponsiveFieldRow(
                                        children: [
                                          AppTextField(
                                            label: l10n.agentProfileFieldPhone,
                                            controller: _formController.telefoneController,
                                            fieldSpec: AppFieldSpecs.phone(l10n),
                                          ),
                                          AppTextField(
                                            label: l10n.agentProfileFieldMobile,
                                            controller: _formController.celularController,
                                            fieldSpec: AppFieldSpecs.mobile(l10n),
                                            validator: (value) => _requiredWithSpec(
                                              l10n,
                                              l10n.agentProfileFieldMobile,
                                              AppFieldSpecs.mobile(l10n),
                                              value,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      AppTextField(
                                        label: l10n.agentProfileFieldEmail,
                                        controller: _formController.emailController,
                                        fieldSpec: AppFieldSpecs.email(l10n),
                                        validator: (value) => _requiredWithSpec(
                                          l10n,
                                          l10n.agentProfileFieldEmail,
                                          AppFieldSpecs.email(l10n),
                                          value,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _AgentProfileSection(
                                  title: l10n.agentProfileSectionAddress,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _ResponsiveFieldActionRow(
                                        field: AppTextField(
                                          label: l10n.agentProfileFieldPostalCode,
                                          controller: _formController.cepController,
                                          fieldSpec: AppFieldSpecs.cep(l10n),
                                          validator: (value) => _requiredWithSpec(
                                            l10n,
                                            l10n.agentProfileFieldPostalCode,
                                            AppFieldSpecs.cep(l10n),
                                            value,
                                          ),
                                        ),
                                        action: AppButton(
                                          label: l10n.agentProfileActionLookupCep,
                                          isPrimary: false,
                                          isLoading: _isLookingUpCep,
                                          onPressed: () {
                                            unawaited(_lookupCep());
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      _ResponsiveFieldRow(
                                        flexes: const [3, 1],
                                        children: [
                                          AppTextField(
                                            label: l10n.agentProfileFieldStreet,
                                            controller: _formController.enderecoController,
                                            validator: (value) => _requiredValidator(
                                              l10n,
                                              l10n.agentProfileFieldStreet,
                                              value,
                                            ),
                                          ),
                                          AppTextField(
                                            label: l10n.agentProfileFieldNumber,
                                            controller: _formController.numeroEnderecoController,
                                            validator: (value) => _requiredValidator(
                                              l10n,
                                              l10n.agentProfileFieldNumber,
                                              value,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      _ResponsiveFieldRow(
                                        flexes: const [2, 2, 1],
                                        children: [
                                          AppTextField(
                                            label: l10n.agentProfileFieldDistrict,
                                            controller: _formController.bairroController,
                                            validator: (value) => _requiredValidator(
                                              l10n,
                                              l10n.agentProfileFieldDistrict,
                                              value,
                                            ),
                                          ),
                                          AppTextField(
                                            label: l10n.agentProfileFieldCity,
                                            controller: _formController.nomeMunicipioController,
                                            validator: (value) => _requiredValidator(
                                              l10n,
                                              l10n.agentProfileFieldCity,
                                              value,
                                            ),
                                          ),
                                          AppTextField(
                                            label: l10n.agentProfileFieldState,
                                            controller: _formController.ufMunicipioController,
                                            fieldSpec: AppFieldSpecs.state(l10n),
                                            validator: (value) => _requiredWithSpec(
                                              l10n,
                                              l10n.agentProfileFieldState,
                                              AppFieldSpecs.state(l10n),
                                              value,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _AgentProfileSection(
                                  title: l10n.agentProfileSectionNotes,
                                  child: AppTextField(
                                    label: l10n.agentProfileFieldNotes,
                                    controller: _formController.observacaoController,
                                    maxLines: 5,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _AgentProfileSaveAction(
                                  isLoading: _isSaving,
                                  saveLabel: l10n.agentProfileActionSave,
                                  onPressed: _saveProfile,
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

class _AgentProfileSection extends StatelessWidget {
  const _AgentProfileSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

class _AgentProfileSaveAction extends StatelessWidget {
  const _AgentProfileSaveAction({
    required this.isLoading,
    required this.saveLabel,
    required this.onPressed,
  });

  final bool isLoading;
  final String saveLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        label: saveLabel,
        isLoading: isLoading,
        onPressed: () {
          unawaited(onPressed());
        },
      ),
    );
  }
}

class _ResponsiveFieldActionRow extends StatelessWidget {
  const _ResponsiveFieldActionRow({
    required this.field,
    required this.action,
  });

  final Widget field;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: action,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: field,
            ),
            const SizedBox(width: AppSpacing.md),
            action,
          ],
        );
      },
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({
    required this.children,
    this.flexes,
  });

  final List<Widget> children;
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(
                flex: flexes?[index] ?? 1,
                child: children[index],
              ),
              if (index < children.length - 1) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
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
    super.key,
  });

  final String? configId;
  final OpenCnpjClient? openCnpjClient;
  final ViaCepClient? viaCepClient;

  @override
  State<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends State<AgentProfilePage> {
  static final RegExp _nonDigitsPattern = RegExp('[^0-9]');

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
    if (!_formController.fieldsInitialized &&
        !configProvider.isLoading &&
        configProvider.currentConfig != null) {
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
    final digits = _digitsOnly(_formController.cnaeCnpjCpfController.text);
    if (digits.length != 14) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleError,
        message: AppStrings.agentProfileLookupCnpjInvalid,
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
        title: AppStrings.modalTitleError,
        message: result.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    _applyOpenCnpjData(result.getOrThrow());
  }

  Future<void> _lookupCep() async {
    final digits = _digitsOnly(_formController.cepController.text);
    if (digits.length != 8) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleError,
        message: AppStrings.agentProfileLookupCepInvalid,
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
        title: AppStrings.modalTitleError,
        message: result.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    _applyViaCepData(result.getOrThrow());
  }

  Future<void> _saveProfile() async {
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
    );

    if (result.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleError,
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

    setState(() {
      _isSaving = false;
    });

    if (saveResult.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: AppStrings.modalTitleErrorSaving,
        message: saveResult.exceptionOrNull()!.toDisplayMessage(),
      );
      return;
    }

    await SettingsFeedback.showSuccess(
      context: context,
      title: AppStrings.modalTitleSuccess,
      message: AppStrings.agentProfileSaveSuccess,
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

  String? _requiredValidator(String label, String? value) {
    if ((value?.trim() ?? '').isEmpty) {
      return AppStrings.formFieldRequired(label);
    }
    return null;
  }

  String? _requiredWithSpec(
    String label,
    FieldSpec fieldSpec,
    String? value,
  ) {
    final requiredError = _requiredValidator(label, value);
    if (requiredError != null) {
      return requiredError;
    }
    return fieldSpec.validator?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = context.watch<ConfigProvider>();
    final isInitialLoading =
        configProvider.isLoading && !_formController.fieldsInitialized;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          AppStrings.agentProfilePageTitle,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: isInitialLoading
              ? const _AgentProfileLoading()
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: AppLayout.scrollbarPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.maxFormWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (configProvider.error.isNotEmpty) ...[
                            InfoBar(
                              title: const Text(AppStrings.modalTitleError),
                              content: Text(configProvider.error),
                              severity: InfoBarSeverity.error,
                              isLong: true,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          SettingsSectionBlock(
                            title: AppStrings.agentProfileSectionIdentity,
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label: AppStrings.agentProfileFieldName,
                                    controller: _formController.nomeController,
                                    validator: (value) => _requiredValidator(
                                      AppStrings.agentProfileFieldName,
                                      value,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppTextField(
                                    label:
                                        AppStrings.agentProfileFieldTradeName,
                                    controller:
                                        _formController.nomeFantasiaController,
                                    validator: (value) => _requiredValidator(
                                      AppStrings.agentProfileFieldTradeName,
                                      value,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppTextField(
                                    label: AppStrings.agentProfileFieldDocument,
                                    controller:
                                        _formController.cnaeCnpjCpfController,
                                    fieldSpec: AppFieldSpecs.document,
                                    validator: (value) => _requiredWithSpec(
                                      AppStrings.agentProfileFieldDocument,
                                      AppFieldSpecs.document,
                                      value,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Button(
                                      onPressed: _isLookingUpCnpj
                                          ? null
                                          : _lookupCnpj,
                                      child: _AsyncButtonLabel(
                                        isLoading: _isLookingUpCnpj,
                                        label: AppStrings
                                            .agentProfileActionLookupCnpj,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SettingsSectionBlock(
                            title: AppStrings.agentProfileSectionContact,
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ResponsiveFieldRow(
                                    children: [
                                      AppTextField(
                                        label:
                                            AppStrings.agentProfileFieldPhone,
                                        controller:
                                            _formController.telefoneController,
                                        fieldSpec: AppFieldSpecs.phone,
                                      ),
                                      AppTextField(
                                        label:
                                            AppStrings.agentProfileFieldMobile,
                                        controller:
                                            _formController.celularController,
                                        fieldSpec: AppFieldSpecs.mobile,
                                        validator: (value) => _requiredWithSpec(
                                          AppStrings.agentProfileFieldMobile,
                                          AppFieldSpecs.mobile,
                                          value,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppTextField(
                                    label: AppStrings.agentProfileFieldEmail,
                                    controller: _formController.emailController,
                                    fieldSpec: AppFieldSpecs.email,
                                    validator: (value) => _requiredWithSpec(
                                      AppStrings.agentProfileFieldEmail,
                                      AppFieldSpecs.email,
                                      value,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SettingsSectionBlock(
                            title: AppStrings.agentProfileSectionAddress,
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    label:
                                        AppStrings.agentProfileFieldPostalCode,
                                    controller: _formController.cepController,
                                    fieldSpec: AppFieldSpecs.cep,
                                    validator: (value) => _requiredWithSpec(
                                      AppStrings.agentProfileFieldPostalCode,
                                      AppFieldSpecs.cep,
                                      value,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Button(
                                      onPressed: _isLookingUpCep
                                          ? null
                                          : _lookupCep,
                                      child: _AsyncButtonLabel(
                                        isLoading: _isLookingUpCep,
                                        label: AppStrings
                                            .agentProfileActionLookupCep,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _ResponsiveFieldRow(
                                    flexes: const [3, 1],
                                    children: [
                                      AppTextField(
                                        label:
                                            AppStrings.agentProfileFieldStreet,
                                        controller:
                                            _formController.enderecoController,
                                        validator: (value) =>
                                            _requiredValidator(
                                              AppStrings
                                                  .agentProfileFieldStreet,
                                              value,
                                            ),
                                      ),
                                      AppTextField(
                                        label:
                                            AppStrings.agentProfileFieldNumber,
                                        controller: _formController
                                            .numeroEnderecoController,
                                        validator: (value) =>
                                            _requiredValidator(
                                              AppStrings
                                                  .agentProfileFieldNumber,
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
                                        label: AppStrings
                                            .agentProfileFieldDistrict,
                                        controller:
                                            _formController.bairroController,
                                        validator: (value) =>
                                            _requiredValidator(
                                              AppStrings
                                                  .agentProfileFieldDistrict,
                                              value,
                                            ),
                                      ),
                                      AppTextField(
                                        label: AppStrings.agentProfileFieldCity,
                                        controller: _formController
                                            .nomeMunicipioController,
                                        validator: (value) =>
                                            _requiredValidator(
                                              AppStrings.agentProfileFieldCity,
                                              value,
                                            ),
                                      ),
                                      AppTextField(
                                        label:
                                            AppStrings.agentProfileFieldState,
                                        controller: _formController
                                            .ufMunicipioController,
                                        fieldSpec: AppFieldSpecs.state,
                                        validator: (value) => _requiredWithSpec(
                                          AppStrings.agentProfileFieldState,
                                          AppFieldSpecs.state,
                                          value,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SettingsSectionBlock(
                            title: AppStrings.agentProfileSectionNotes,
                            child: AppCard(
                              child: AppTextField(
                                label: AppStrings.agentProfileFieldNotes,
                                controller:
                                    _formController.observacaoController,
                                maxLines: 5,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _isSaving ? null : _saveProfile,
                              child: _AsyncButtonLabel(
                                isLoading: _isSaving,
                                label: AppStrings.agentProfileActionSave,
                              ),
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
  const _AgentProfileLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(),
          SizedBox(height: AppSpacing.md),
          Text(AppStrings.agentProfileLoading),
        ],
      ),
    );
  }
}

class _AsyncButtonLabel extends StatelessWidget {
  const _AsyncButtonLabel({
    required this.isLoading,
    required this.label,
  });

  final bool isLoading;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return Text(label);
    }

    return const SizedBox(
      width: 18,
      height: 18,
      child: ProgressRing(strokeWidth: 2),
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
                if (index < children.length - 1)
                  const SizedBox(height: AppSpacing.md),
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
              if (index < children.length - 1)
                const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

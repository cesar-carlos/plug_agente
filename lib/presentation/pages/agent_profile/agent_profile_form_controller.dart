import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/shared/widgets/common/form/brazilian_field_formatters.dart';

/// Holds the [TextEditingController]s used by the agent profile page.
///
/// Each settings page now owns a controller focused on the fields it
/// actually edits, avoiding a single data-clump controller shared across
/// pages with different responsibilities.
class AgentProfileFormController {
  final nameController = TextEditingController();
  final tradeNameController = TextEditingController();
  final documentController = TextEditingController();
  final phoneController = TextEditingController();
  final mobileController = TextEditingController();
  final emailController = TextEditingController();
  final streetController = TextEditingController();
  final addressNumberController = TextEditingController();
  final districtController = TextEditingController();
  final postalCodeController = TextEditingController();
  final cityController = TextEditingController();
  final stateController = TextEditingController();
  final notesController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

  /// Clears every controller and the initialization guard so that the next
  /// call to [initializeFromConfig] populates the form for a new [Config].
  void resetForConfig() {
    _fieldsInitialized = false;
    nameController.clear();
    tradeNameController.clear();
    documentController.clear();
    phoneController.clear();
    mobileController.clear();
    emailController.clear();
    streetController.clear();
    addressNumberController.clear();
    districtController.clear();
    postalCodeController.clear();
    cityController.clear();
    stateController.clear();
    notesController.clear();
  }

  /// Populates empty controllers from the persisted [Config].
  ///
  /// Fields the user has already touched are preserved to avoid losing
  /// in-progress edits when the underlying provider finishes loading.
  void initializeFromConfig(Config? config) {
    if (_fieldsInitialized || config == null) {
      return;
    }

    _setIfEmpty(nameController, config.nome);
    _setIfEmpty(tradeNameController, config.nomeFantasia);
    _setIfEmpty(documentController, config.cnaeCnpjCpf);
    _setIfEmpty(phoneController, config.telefone);
    _setIfEmpty(mobileController, config.celular);
    _setIfEmpty(emailController, config.email);
    _setIfEmpty(streetController, config.endereco);
    _setIfEmpty(addressNumberController, config.numeroEndereco);
    _setIfEmpty(districtController, config.bairro);
    _setIfEmpty(postalCodeController, config.cep);
    _setIfEmpty(cityController, config.nomeMunicipio);
    _setIfEmpty(stateController, config.ufMunicipio);
    _setIfEmpty(notesController, config.observacao);

    _fieldsInitialized = true;
  }

  /// Mirrors the validated [profile] back into the controllers, applying
  /// Brazilian field masks so the user sees formatted values.
  void applyValidatedProfile(AgentProfile profile) {
    _setTrimmedText(nameController, profile.name);
    _setTrimmedText(tradeNameController, profile.tradeName);
    BrazilianFieldFormatters.apply(
      documentController,
      profile.document,
      BrazilianFieldFormatters.document,
    );

    final phone = profile.phone;
    if (phone != null && phone.isNotEmpty) {
      BrazilianFieldFormatters.apply(
        phoneController,
        phone,
        BrazilianFieldFormatters.phone,
      );
    } else {
      phoneController.clear();
    }

    BrazilianFieldFormatters.apply(
      mobileController,
      profile.mobile,
      BrazilianFieldFormatters.phone,
    );
    _setTrimmedText(emailController, profile.email);
    _setTrimmedText(streetController, profile.address.street);
    _setTrimmedText(addressNumberController, profile.address.number);
    _setTrimmedText(districtController, profile.address.district);
    BrazilianFieldFormatters.apply(
      postalCodeController,
      profile.address.postalCode,
      BrazilianFieldFormatters.postalCode,
    );
    _setTrimmedText(cityController, profile.address.city);
    BrazilianFieldFormatters.apply(
      stateController,
      profile.address.state,
      BrazilianFieldFormatters.state,
    );
    notesController.text = profile.notes ?? '';
  }

  void applyOpenCnpjData(OpenCnpjCompanyData data) {
    BrazilianFieldFormatters.apply(
      documentController,
      data.cnpj,
      BrazilianFieldFormatters.document,
    );
    _setTrimmedText(nameController, data.legalName);
    _setOptionalText(tradeNameController, data.tradeName);
    _setOptionalText(emailController, data.email);
    _setOptionalFormatted(phoneController, data.phone, BrazilianFieldFormatters.phone);
    _setOptionalFormatted(mobileController, data.mobile, BrazilianFieldFormatters.phone);
    _setOptionalText(streetController, data.street);
    _setOptionalText(addressNumberController, data.number);
    _setOptionalText(districtController, data.district);
    _setOptionalFormatted(postalCodeController, data.postalCode, BrazilianFieldFormatters.postalCode);
    _setOptionalText(cityController, data.city);
    _setOptionalFormatted(stateController, data.state, BrazilianFieldFormatters.state);
  }

  void applyViaCepData(ViaCepAddress data) {
    BrazilianFieldFormatters.apply(
      postalCodeController,
      data.cep,
      BrazilianFieldFormatters.postalCode,
    );
    _setTrimmedText(streetController, data.logradouro);
    _setTrimmedText(districtController, data.bairro);
    _setTrimmedText(cityController, data.localidade);
    BrazilianFieldFormatters.apply(
      stateController,
      data.uf,
      BrazilianFieldFormatters.state,
    );
  }

  void dispose() {
    nameController.dispose();
    tradeNameController.dispose();
    documentController.dispose();
    phoneController.dispose();
    mobileController.dispose();
    emailController.dispose();
    streetController.dispose();
    addressNumberController.dispose();
    districtController.dispose();
    postalCodeController.dispose();
    cityController.dispose();
    stateController.dispose();
    notesController.dispose();
  }

  void _setIfEmpty(TextEditingController controller, String value) {
    if (controller.text.isEmpty) {
      controller.text = value;
    }
  }

  void _setTrimmedText(TextEditingController controller, String value) {
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
}

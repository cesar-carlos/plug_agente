import 'package:flutter/material.dart';

import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

class ConfigFormController {
  final serverUrlController = TextEditingController();
  final agentIdController = TextEditingController();
  final authUsernameController = TextEditingController();
  final authPasswordController = TextEditingController();
  final driverNameController = TextEditingController();
  final odbcDriverNameController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final databaseNameController = TextEditingController();
  final hostController = TextEditingController();
  final portController = TextEditingController();
  final nomeController = TextEditingController();
  final nomeFantasiaController = TextEditingController();
  final cnaeCnpjCpfController = TextEditingController();
  final telefoneController = TextEditingController();
  final celularController = TextEditingController();
  final emailController = TextEditingController();
  final enderecoController = TextEditingController();
  final numeroEnderecoController = TextEditingController();
  final bairroController = TextEditingController();
  final cepController = TextEditingController();
  final nomeMunicipioController = TextEditingController();
  final ufMunicipioController = TextEditingController();
  final observacaoController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

  /// Clears all fields and the initialization guard so that a subsequent
  /// [initializeFromConfig] call always re-populates for the new [Config].
  /// Call this whenever the active config id changes.
  void resetForConfig() {
    _fieldsInitialized = false;
    serverUrlController.clear();
    agentIdController.clear();
    authUsernameController.clear();
    authPasswordController.clear();
    driverNameController.clear();
    odbcDriverNameController.clear();
    usernameController.clear();
    passwordController.clear();
    databaseNameController.clear();
    hostController.clear();
    portController.clear();
    nomeController.clear();
    nomeFantasiaController.clear();
    cnaeCnpjCpfController.clear();
    telefoneController.clear();
    celularController.clear();
    emailController.clear();
    enderecoController.clear();
    numeroEnderecoController.clear();
    bairroController.clear();
    cepController.clear();
    nomeMunicipioController.clear();
    ufMunicipioController.clear();
    observacaoController.clear();
  }

  void initializeFromConfig(Config? config) {
    if (_fieldsInitialized || config == null) return;

    if (serverUrlController.text.isEmpty) {
      serverUrlController.text = config.serverUrl;
    }
    if (agentIdController.text.isEmpty) {
      agentIdController.text = config.agentId;
    }
    if (authUsernameController.text.isEmpty) {
      authUsernameController.text = config.authUsername ?? '';
    }
    if (authPasswordController.text.isEmpty) {
      authPasswordController.text = config.authPassword ?? '';
    }
    if (driverNameController.text.isEmpty) {
      driverNameController.text = config.driverName;
    }
    if (odbcDriverNameController.text.isEmpty) {
      odbcDriverNameController.text = config.odbcDriverName;
    }
    if (usernameController.text.isEmpty) {
      usernameController.text = config.username;
    }
    if (passwordController.text.isEmpty) {
      passwordController.text = config.password ?? '';
    }
    if (databaseNameController.text.isEmpty) {
      databaseNameController.text = config.databaseName;
    }
    if (hostController.text.isEmpty) {
      hostController.text = config.host;
    }
    if (portController.text.isEmpty) {
      portController.text = config.port.toString();
    }
    if (nomeController.text.isEmpty) {
      nomeController.text = config.nome;
    }
    if (nomeFantasiaController.text.isEmpty) {
      nomeFantasiaController.text = config.nomeFantasia;
    }
    if (cnaeCnpjCpfController.text.isEmpty) {
      cnaeCnpjCpfController.text = config.cnaeCnpjCpf;
    }
    if (telefoneController.text.isEmpty) {
      telefoneController.text = config.telefone;
    }
    if (celularController.text.isEmpty) {
      celularController.text = config.celular;
    }
    if (emailController.text.isEmpty) {
      emailController.text = config.email;
    }
    if (enderecoController.text.isEmpty) {
      enderecoController.text = config.endereco;
    }
    if (numeroEnderecoController.text.isEmpty) {
      numeroEnderecoController.text = config.numeroEndereco;
    }
    if (bairroController.text.isEmpty) {
      bairroController.text = config.bairro;
    }
    if (cepController.text.isEmpty) {
      cepController.text = config.cep;
    }
    if (nomeMunicipioController.text.isEmpty) {
      nomeMunicipioController.text = config.nomeMunicipio;
    }
    if (ufMunicipioController.text.isEmpty) {
      ufMunicipioController.text = config.ufMunicipio;
    }
    if (observacaoController.text.isEmpty) {
      observacaoController.text = config.observacao;
    }

    _fieldsInitialized = true;
  }

  void updateAllFieldsToProvider(ConfigProvider configProvider) {
    configProvider.updateHost(hostController.text);
    configProvider.updatePort(int.tryParse(portController.text) ?? 1433);
    configProvider.updateDatabaseName(databaseNameController.text);
    configProvider.updateUsername(usernameController.text);
    configProvider.updatePassword(passwordController.text);
    configProvider.updateDriverName(driverNameController.text);
    configProvider.updateOdbcDriverName(odbcDriverNameController.text);
    configProvider.updateServerUrl(serverUrlController.text);
    configProvider.updateAgentId(agentIdController.text);
    configProvider.updateAuthUsername(
      authUsernameController.text.trim().isEmpty ? null : authUsernameController.text.trim(),
    );
    configProvider.updateAuthPassword(
      authPasswordController.text.trim().isEmpty ? null : authPasswordController.text.trim(),
    );
    configProvider.updateNome(nomeController.text);
    configProvider.updateNomeFantasia(nomeFantasiaController.text);
    configProvider.updateCnaeCnpjCpf(cnaeCnpjCpfController.text);
    configProvider.updateTelefone(telefoneController.text);
    configProvider.updateCelular(celularController.text);
    configProvider.updateEmail(emailController.text);
    configProvider.updateEndereco(enderecoController.text);
    configProvider.updateNumeroEndereco(numeroEnderecoController.text);
    configProvider.updateBairro(bairroController.text);
    configProvider.updateCep(cepController.text);
    configProvider.updateNomeMunicipio(nomeMunicipioController.text);
    configProvider.updateUfMunicipio(ufMunicipioController.text);
    configProvider.updateObservacao(observacaoController.text);
  }

  void dispose() {
    serverUrlController.dispose();
    agentIdController.dispose();
    authUsernameController.dispose();
    authPasswordController.dispose();
    driverNameController.dispose();
    odbcDriverNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    databaseNameController.dispose();
    hostController.dispose();
    portController.dispose();
    nomeController.dispose();
    nomeFantasiaController.dispose();
    cnaeCnpjCpfController.dispose();
    telefoneController.dispose();
    celularController.dispose();
    emailController.dispose();
    enderecoController.dispose();
    numeroEnderecoController.dispose();
    bairroController.dispose();
    cepController.dispose();
    nomeMunicipioController.dispose();
    ufMunicipioController.dispose();
    observacaoController.dispose();
  }
}

import 'package:flutter/material.dart';

import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

class ConfigFormController {
  final TextEditingController serverUrlController = TextEditingController();
  final TextEditingController agentIdController = TextEditingController();
  final TextEditingController authUsernameController = TextEditingController();
  final TextEditingController authPasswordController = TextEditingController();
  final TextEditingController driverNameController = TextEditingController();
  final TextEditingController odbcDriverNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController databaseNameController = TextEditingController();
  final TextEditingController hostController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  final TextEditingController nomeController = TextEditingController();
  final TextEditingController nomeFantasiaController = TextEditingController();
  final TextEditingController cnaeCnpjCpfController = TextEditingController();
  final TextEditingController telefoneController = TextEditingController();
  final TextEditingController celularController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController enderecoController = TextEditingController();
  final TextEditingController numeroEnderecoController = TextEditingController();
  final TextEditingController bairroController = TextEditingController();
  final TextEditingController cepController = TextEditingController();
  final TextEditingController nomeMunicipioController = TextEditingController();
  final TextEditingController ufMunicipioController = TextEditingController();
  final TextEditingController observacaoController = TextEditingController();

  bool _fieldsInitialized = false;
  bool get fieldsInitialized => _fieldsInitialized;

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

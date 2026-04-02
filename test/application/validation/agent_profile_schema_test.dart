import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  group('AgentProfile', () {
    test('should normalize valid form fields', () {
      final result = AgentProfile.fromFormFields(
        name: 'Empresa Exemplo',
        tradeName: 'Fantasia Exemplo',
        document: '529.982.247-25',
        phone: '(11) 3333-4444',
        mobile: '(11) 98888-7777',
        email: 'CONTATO@EXEMPLO.COM ',
        street: 'Rua Central',
        number: '123',
        district: 'Centro',
        postalCode: '01001-000',
        city: 'Sao Paulo',
        state: 'sp',
        notes: 'Observacao de teste',
      );

      check(result.isSuccess()).isTrue();
      final profile = result.getOrThrow();
      check(profile.document).equals('52998224725');
      check(profile.documentType).equals('cpf');
      check(profile.phone).equals('1133334444');
      check(profile.mobile).equals('11988887777');
      check(profile.email).equals('contato@exemplo.com');
      check(profile.address.postalCode).equals('01001000');
      check(profile.address.state).equals('SP');
    });

    test('should fail when city and state are missing', () {
      final result = AgentProfile.fromFormFields(
        name: 'Empresa Exemplo',
        tradeName: 'Fantasia Exemplo',
        document: '529.982.247-25',
        phone: '',
        mobile: '(11) 98888-7777',
        email: 'contato@exemplo.com',
        street: 'Rua Central',
        number: '123',
        district: 'Centro',
        postalCode: '01001-000',
        city: '',
        state: '',
        notes: '',
      );

      check(result.isError()).isTrue();
      final failure = result.exceptionOrNull()! as domain.ValidationFailure;
      check(failure.message).contains('Municipio');
      check(failure.message).contains('UF');
    });

    test('should produce correct toJson round-trip from Config', () {
      final now = DateTime(2026, 1, 15, 12);
      final config = Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17',
        connectionString: 'DSN=Test',
        username: 'u',
        databaseName: 'db',
        host: 'localhost',
        port: 1433,
        nome: 'Empresa Exemplo',
        nomeFantasia: 'Fantasia Exemplo',
        cnaeCnpjCpf: '529.982.247-25',
        telefone: '(11) 3333-4444',
        celular: '(11) 98888-7777',
        email: 'CONTATO@EXEMPLO.COM',
        endereco: 'Rua Central',
        numeroEndereco: '123',
        bairro: 'Centro',
        cep: '01001-000',
        nomeMunicipio: 'Sao Paulo',
        ufMunicipio: 'sp',
        observacao: 'Nota',
        createdAt: now,
        updatedAt: now,
      );

      final result = AgentProfile.fromConfig(config);

      check(result.isSuccess()).isTrue();
      final json = result.getOrThrow().toJson();
      check(json['name']).equals('Empresa Exemplo');
      check(json['trade_name']).equals('Fantasia Exemplo');
      check(json['document']).equals('52998224725');
      check(json['document_type']).equals('cpf');
      check(json['phone']).equals('1133334444');
      check(json['mobile']).equals('11988887777');
      check(json['email']).equals('contato@exemplo.com');
      check(json['notes']).equals('Nota');
      final address = json['address'] as Map<String, dynamic>;
      check(address['postal_code']).equals('01001000');
      check(address['state']).equals('SP');
      check(address['city']).equals('Sao Paulo');
    });

    test('should omit phone and notes from toJson when empty', () {
      final now = DateTime(2026);
      final config = Config(
        id: 'cfg-2',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17',
        connectionString: 'DSN=Test',
        username: 'u',
        databaseName: 'db',
        host: 'localhost',
        port: 1433,
        nome: 'Empresa',
        nomeFantasia: 'Fantasia',
        cnaeCnpjCpf: '52998224725',
        celular: '11988887777',
        email: 'a@b.com',
        endereco: 'Rua A',
        numeroEndereco: '1',
        bairro: 'Bairro',
        cep: '01001000',
        nomeMunicipio: 'Cidade',
        ufMunicipio: 'SP',
        createdAt: now,
        updatedAt: now,
      );

      final result = AgentProfile.fromConfig(config);

      check(result.isSuccess()).isTrue();
      final json = result.getOrThrow().toJson();
      check(json.containsKey('phone')).isFalse();
      check(json.containsKey('notes')).isFalse();
    });
  });
}

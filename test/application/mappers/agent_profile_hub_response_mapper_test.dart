import 'package:checks/checks.dart';
import 'package:plug_agente/application/mappers/agent_profile_hub_response_mapper.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_catalog_snapshot.dart';
import 'package:test/test.dart';

void main() {
  test('should map hub camelCase agent payload to AgentProfile', () {
    const snapshot = AgentHubProfileCatalogSnapshot(
      profileVersion: 2,
      agentPayload: <String, dynamic>{
        'name': 'ACME LTDA',
        'tradeName': 'ACME',
        'document': '59261947000107',
        'documentType': 'cnpj',
        'mobile': '65992865050',
        'email': 'a@b.com',
        'address': <String, dynamic>{
          'street': 'Av Brasil',
          'number': '130',
          'district': 'Centro',
          'postalCode': '78300096',
          'city': 'Tangará da Serra',
          'state': 'mt',
        },
      },
    );

    final result = agentProfileFromHubCatalogSnapshot(snapshot);

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.tradeName).equals('ACME');
    check(result.getOrNull()?.address.postalCode).equals('78300096');
    check(result.getOrNull()?.address.state).equals('MT');
  });
}

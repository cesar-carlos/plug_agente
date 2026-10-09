import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';

void main() {
  for (final effect in <Object?>['deny_typo', '', null, 42]) {
    test('rejects invalid rule effect $effect instead of granting access', () {
      expect(() => ClientTokenRule.fromJson({'effect': effect}), throwsFormatException);
    });
  }
  test('preserves the legacy default and normalizes supported effect names', () {
    expect(ClientTokenRule.fromJson({}).effect, ClientTokenRuleEffect.allow);
    expect(ClientTokenRule.fromJson({'effect': ' DENY '}).effect, ClientTokenRuleEffect.deny);
    expect(ClientTokenRule.fromJson({'effect': 'ALLOW'}).effect, ClientTokenRuleEffect.allow);
  });
  test('rejects unknown resource types and non-boolean permissions before typed getters', () {
    expect(() => ClientTokenRule.fromJson({'effect': 'deny', 'resource_type': 'typo'}), throwsFormatException);
    expect(() => ClientTokenRule.fromJson({'effect': 'deny', 'read': 'true'}), throwsFormatException);
  });
}

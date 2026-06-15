import 'package:flutter_test/flutter_test.dart';

import '../../tool/agent_actions/agent_action_security_gate_checklist.dart';

void main() {
  test('should expose threat model summary for every MVP action type', () {
    for (final type in agentActionSecurityGateMvpTypes) {
      expect(
        threatModelSummaryFor(type),
        isNotNull,
        reason: 'missing threat model summary for $type',
      );
      expect(threatModelSummaryFor(type)!.trim(), isNotEmpty);
    }
  });

  test('should return unknown summary for unsupported type', () {
    expect(threatModelSummaryFor('unknownType'), isNull);
  });

  test('should resolve CLI types or default to MVP list', () {
    expect(resolveSecurityGateActionTypes(const <String>[]), agentActionSecurityGateMvpTypes);
    expect(
      resolveSecurityGateActionTypes(const <String>['jar', '--verbose']),
      <String>['jar'],
    );
  });
}

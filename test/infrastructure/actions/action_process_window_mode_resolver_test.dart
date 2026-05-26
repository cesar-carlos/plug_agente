import 'dart:io';

import 'package:checks/checks.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_window_mode_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ActionProcessWindowModeResolver', () {
    test('should map window modes to process start modes', () {
      check(
        ActionProcessWindowModeResolver.resolve(AgentActionProcessWindowMode.normal),
      ).equals(ProcessStartMode.normal);
      check(
        ActionProcessWindowModeResolver.resolve(AgentActionProcessWindowMode.minimized),
      ).equals(ProcessStartMode.normal);
      if (Platform.isWindows) {
        check(
          ActionProcessWindowModeResolver.resolve(AgentActionProcessWindowMode.hidden),
        ).equals(ProcessStartMode.detached);
      }
    });
  });
}

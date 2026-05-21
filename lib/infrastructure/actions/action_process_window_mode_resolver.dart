import 'dart:io';

import 'package:plug_agente/domain/actions/actions.dart';

/// Maps [AgentActionProcessWindowMode] to [ProcessStartMode] for local runners.
abstract final class ActionProcessWindowModeResolver {
  static ProcessStartMode resolve(AgentActionProcessWindowMode mode) {
    if (!Platform.isWindows) {
      return ProcessStartMode.normal;
    }

    return switch (mode) {
      AgentActionProcessWindowMode.normal => ProcessStartMode.normal,
      // Best-effort on Windows: detached avoids inheriting the agent console.
      AgentActionProcessWindowMode.hidden => ProcessStartMode.detached,
      // Dart does not expose STARTF_USESHOWWINDOW=SW_MINIMIZE; keep normal start.
      AgentActionProcessWindowMode.minimized => ProcessStartMode.normal,
    };
  }
}

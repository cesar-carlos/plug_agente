import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';

/// Provider for runtime mode and capabilities (read-only).
class RuntimeModeProvider extends ChangeNotifier {
  RuntimeModeProvider(this._capabilities);

  final RuntimeCapabilities _capabilities;

  RuntimeCapabilities get capabilities => _capabilities;

  bool get isFullySupported => _capabilities.isFullySupported;
  bool get isDegraded => _capabilities.isDegraded;
  bool get isUnsupported => _capabilities.isUnsupported;

  bool get supportsTray => _capabilities.supportsTray;
  bool get supportsNotifications => _capabilities.supportsNotifications;
  bool get supportsAutoUpdate => _capabilities.supportsAutoUpdate;
  bool get supportsWindowManager => _capabilities.supportsWindowManager;

  List<String> get degradationReasons => _capabilities.degradationReasons;
}

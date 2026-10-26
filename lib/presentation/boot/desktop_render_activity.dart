import 'package:flutter/widgets.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';

/// Keeps background work alive while suspending invisible UI animations.
class DesktopRenderActivity extends StatelessWidget {
  const DesktopRenderActivity({required this.activity, required this.child, super.key});

  final IWindowRenderActivity? activity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final source = activity;
    if (source == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: source.renderingEnabled,
      child: child,
      builder: (context, enabled, child) => TickerMode(enabled: enabled, child: child!),
    );
  }
}

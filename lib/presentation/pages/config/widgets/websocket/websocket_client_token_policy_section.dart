import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class WebSocketClientTokenPolicySection extends StatefulWidget {
  const WebSocketClientTokenPolicySection({super.key});

  @override
  State<WebSocketClientTokenPolicySection> createState() => _WebSocketClientTokenPolicySectionState();
}

class _WebSocketClientTokenPolicySectionState extends State<WebSocketClientTokenPolicySection> {
  late bool _introspectionEnabled;
  bool _isPersisting = false;

  FeatureFlags get _flags => context.read<FeatureFlags>();

  @override
  void initState() {
    super.initState();
    _introspectionEnabled = context.read<FeatureFlags>().enableClientTokenPolicyIntrospection;
  }

  Future<void> _onChanged(bool enabled) async {
    if (_isPersisting) {
      return;
    }
    setState(() {
      _isPersisting = true;
      _introspectionEnabled = enabled;
    });
    try {
      await _flags.setEnableClientTokenPolicyIntrospection(enabled);
    } finally {
      if (mounted) {
        setState(() {
          _isPersisting = false;
          _introspectionEnabled = _flags.enableClientTokenPolicyIntrospection;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      child: SettingsSectionBlock(
        title: l10n.wsSectionClientTokenPolicy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToggleSwitch(
              checked: _introspectionEnabled,
              onChanged: _isPersisting ? null : (bool value) => unawaited(_onChanged(value)),
              content: Text(l10n.wsFieldClientTokenPolicyIntrospection),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsClientTokenPolicyIntrospectionDescription,
              style: context.captionText,
            ),
          ],
        ),
      ),
    );
  }
}

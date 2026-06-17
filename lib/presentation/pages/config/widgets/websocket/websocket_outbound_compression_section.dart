import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class WebSocketOutboundCompressionSection extends StatefulWidget {
  const WebSocketOutboundCompressionSection({super.key});

  @override
  State<WebSocketOutboundCompressionSection> createState() => _WebSocketOutboundCompressionSectionState();
}

class _WebSocketOutboundCompressionSectionState extends State<WebSocketOutboundCompressionSection> {
  late OutboundCompressionMode _mode;
  bool _isPersisting = false;

  FeatureFlags get _flags => getIt<FeatureFlags>();

  @override
  void initState() {
    super.initState();
    _mode = getIt<FeatureFlags>().outboundCompressionMode;
  }

  Future<void> _onModeChanged(OutboundCompressionMode mode) async {
    if (_isPersisting || mode == _mode) {
      return;
    }
    setState(() {
      _isPersisting = true;
      _mode = mode;
    });
    var persisted = true;
    try {
      await _flags.setOutboundCompressionMode(mode);
    } on Object catch (error, stackTrace) {
      persisted = false;
      AppLogger.error('Failed to persist outbound compression mode', error, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isPersisting = false;
          _mode = _flags.outboundCompressionMode;
        });
        if (!persisted) {
          final l10n = AppLocalizations.of(context)!;
          SettingsFeedback.showError(
            context: context,
            title: l10n.modalTitleError,
            message: l10n.settingsPersistError,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      child: SettingsSectionBlock(
        title: l10n.wsSectionOutboundCompression,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<OutboundCompressionMode>(
              label: l10n.wsFieldOutboundCompressionMode,
              value: _mode,
              items: [
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.none,
                  child: Text(l10n.wsOutboundCompressionOff),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.auto,
                  child: Text(l10n.wsOutboundCompressionAuto),
                ),
                ComboBoxItem<OutboundCompressionMode>(
                  value: OutboundCompressionMode.gzip,
                  child: Text(l10n.wsOutboundCompressionGzip),
                ),
              ],
              onChanged: _isPersisting
                  ? null
                  : (OutboundCompressionMode? value) {
                      if (value != null) {
                        unawaited(_onModeChanged(value));
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsOutboundCompressionDescription,
              style: context.captionText,
            ),
          ],
        ),
      ),
    );
  }
}

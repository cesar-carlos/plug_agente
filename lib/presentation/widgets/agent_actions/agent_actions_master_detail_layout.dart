import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class AgentActionsMasterDetailLayout extends StatelessWidget {
  const AgentActionsMasterDetailLayout({
    required this.master,
    required this.detail,
    super.key,
  });

  static const double _stackedBreakpoint = 1180;
  static const double _masterPanelWidth = 720;
  static const double _minStackedMasterHeight = 220;
  static const double _maxStackedMasterHeight = 320;

  final Widget master;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackedBreakpoint) {
          final masterHeight = math.min(
            _maxStackedMasterHeight,
            math.max(_minStackedMasterHeight, constraints.maxHeight * 0.34),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: masterHeight,
                child: master,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _masterPanelWidth,
              child: master,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

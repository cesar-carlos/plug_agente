import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class UpdateMaintenanceSurface extends StatefulWidget {
  const UpdateMaintenanceSurface({required this.admission, required this.child, required this.reconcile, super.key});

  final UpdateMaintenanceAdmission admission;
  final Widget child;
  final Future<void> Function() reconcile;

  @override
  State<UpdateMaintenanceSurface> createState() => _UpdateMaintenanceSurfaceState();
}

class _UpdateMaintenanceSurfaceState extends State<UpdateMaintenanceSurface> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _reconcile() async {
    setState(() { _busy = true; _failed = false; });
    try {
      await widget.reconcile();
    } on Object catch (error, stack) {
      developer.log('Manual updater reconciliation failed', error: error, stackTrace: stack);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<UpdateMaintenancePhase>(
    stream: widget.admission.changes,
    initialData: widget.admission.phase,
    builder: (context, snapshot) {
      final phase = snapshot.data ?? widget.admission.phase;
      final blocked = phase != UpdateMaintenancePhase.operational;
      final recovery = phase == UpdateMaintenancePhase.dispatchUnknown || phase == UpdateMaintenancePhase.recoveryRequired;
      final l10n = AppLocalizations.of(context)!;
      return Column(children: [
        if (blocked) Padding(padding: const EdgeInsets.all(8), child: InfoBar(
          title: Text(recovery ? l10n.updateRecoveryTitle : l10n.updateMaintenanceTitle),
          content: SelectableText(_failed ? l10n.updateRecoveryRetryFailed : recovery ? l10n.updateRecoveryDescription : l10n.updateMaintenanceDescription),
          severity: recovery ? InfoBarSeverity.error : InfoBarSeverity.warning,
          action: recovery ? Button(onPressed: _busy ? null : _reconcile,
            child: Text(l10n.updateReconcileAction)) : null,
        )),
        Expanded(child: ExcludeFocus(excluding: blocked,
          child: AbsorbPointer(key: const ValueKey('update-maintenance-input'), absorbing: blocked, child: widget.child))),
      ]);
    },
  );
}

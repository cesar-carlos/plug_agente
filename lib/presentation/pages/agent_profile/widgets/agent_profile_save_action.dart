import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

/// Save button driven by [ValueListenable]s so the surrounding form is not
/// rebuilt when only the save state changes.
///
/// The widget is layout-neutral: callers decide whether to wrap it in
/// `Align`, `Padding`, etc. when placing it in the page footer or in the
/// `PageHeader.commandBar`.
class AgentProfileSaveAction extends StatelessWidget {
  const AgentProfileSaveAction({
    required this.isSaving,
    required this.canSave,
    required this.saveLabel,
    required this.onPressed,
    super.key,
  });

  final ValueListenable<bool> isSaving;
  final ValueListenable<bool> canSave;
  final String saveLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    // `canSave` already encodes the saving state, so listening to it alone
    // is enough to refresh both the loading and the enabled status.
    return ValueListenableBuilder<bool>(
      valueListenable: canSave,
      builder: (context, enabled, _) {
        final saving = isSaving.value;
        return AppButton(
          label: saveLabel,
          isLoading: saving,
          onPressed: enabled
              ? () async {
                  await onPressed();
                }
              : null,
        );
      },
    );
  }
}

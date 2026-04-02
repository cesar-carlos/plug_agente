import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/shared/widgets/common/common.dart';
import 'package:plug_agente/shared/widgets/sql/sql_visual_identity.dart';

class SqlEditor extends StatelessWidget {
  const SqlEditor({
    super.key,
    this.controller,
    this.onChanged,
    this.validator,
    this.maxLines = 6,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: SqlVisualIdentity.editorPanelPadding,
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: SqlVisualIdentity.panelBorderRadius,
      ),
      child: AppTextField(
        label: AppStrings.querySqlLabel,
        hint: AppStrings.querySqlHint,
        controller: controller,
        onChanged: onChanged,
        validator: validator,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}

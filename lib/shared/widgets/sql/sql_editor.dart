import 'package:flutter/widgets.dart';

import '../common/common.dart';

class SqlEditor extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  const SqlEditor({super.key, this.controller, this.onChanged, this.validator});

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: 'Consulta SQL',
      hint: 'SELECT * FROM tabela...',
      controller: controller,
      onChanged: onChanged,
      validator: validator,
      maxLines: 10,
      keyboardType: TextInputType.multiline,
    );
  }
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class WebSocketLogMetaRow extends StatelessWidget {
  const WebSocketLogMetaRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        style: context.bodyMuted.copyWith(fontSize: 11),
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: context.bodyText.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

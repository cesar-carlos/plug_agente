import 'package:flutter/widgets.dart';

/// Rebuilds [builder] only when [selector] returns a new token.
///
/// Use this instead of [ListenableBuilder] on `AgentActionsProvider` so a
/// queue tick or history refresh does not rebuild unrelated surfaces
/// (actions grid, editor, settings). Works without `Provider.of`, so dialogs
/// that only receive the notifier instance can still listen selectively.
class AgentActionsSelectBuilder extends StatefulWidget {
  const AgentActionsSelectBuilder({
    required this.listenable,
    required this.selector,
    required this.builder,
    super.key,
  });

  final Listenable listenable;
  final int Function() selector;
  final Widget Function(BuildContext context) builder;

  @override
  State<AgentActionsSelectBuilder> createState() => _AgentActionsSelectBuilderState();
}

class _AgentActionsSelectBuilderState extends State<AgentActionsSelectBuilder> {
  late int _token;

  @override
  void initState() {
    super.initState();
    _token = widget.selector();
    widget.listenable.addListener(_onListenableChanged);
  }

  @override
  void didUpdateWidget(covariant AgentActionsSelectBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onListenableChanged);
      widget.listenable.addListener(_onListenableChanged);
    }
    _token = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onListenableChanged);
    super.dispose();
  }

  void _onListenableChanged() {
    if (!mounted) {
      return;
    }

    final next = widget.selector();
    if (next == _token) {
      return;
    }

    setState(() {
      _token = next;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

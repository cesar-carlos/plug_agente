/// Stable page order for the action editor.
///
/// Section indexes come from validation (`0` identity, `1` target, `2` limits,
/// `3` advanced, `4` notifications, `5` schedule). The page strip uses the
/// reading order below.
abstract final class AgentActionEditorPages {
  static const List<String> order = [
    'identity',
    'target',
    'schedule',
    'limits',
    'advanced',
    'notifications',
  ];

  static int indexForSection(int section) {
    const ids = <int, String>{
      0: 'identity',
      1: 'target',
      2: 'limits',
      3: 'advanced',
      4: 'notifications',
      5: 'schedule',
    };
    final id = ids[section] ?? 'identity';
    final index = order.indexOf(id);
    return index < 0 ? 0 : index;
  }
}

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Item for [AppFluentTabView] (icon, label, body).
class AppFluentTabItem {
  const AppFluentTabItem({
    required this.icon,
    required this.text,
    required this.body,
  });

  final IconData icon;
  final String text;
  final Widget body;
}

/// Fluent `TabView` wrapper for consistent tabbed surfaces (settings, dashboard).
///
/// When there is only one item, the tab strip is omitted and the body is shown
/// directly to avoid a redundant single tab.
class AppFluentTabView extends StatelessWidget {
  const AppFluentTabView({
    required this.currentIndex,
    required this.onChanged,
    required this.items,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<AppFluentTabItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) {
      if (items.isEmpty) {
        return const SizedBox.shrink();
      }
      return KeyedSubtree(
        key: const ValueKey('app_fluent_tab_view_single'),
        child: items.first.body,
      );
    }
    return TabView(
      currentIndex: currentIndex,
      onChanged: onChanged,
      minTabWidth: 180,
      tabs: items
          .map(
            (AppFluentTabItem item) => Tab(
              icon: Icon(item.icon),
              text: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(item.text),
              ),
              body: item.body,
            ),
          )
          .toList(growable: false),
    );
  }
}

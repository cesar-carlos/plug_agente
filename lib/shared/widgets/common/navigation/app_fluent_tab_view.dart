import 'package:fluent_ui/fluent_ui.dart';

/// Item for [AppFluentTabView] (icon, label, body).
class AppFluentTabItem {
  const AppFluentTabItem({
    required this.icon,
    required this.text,
    required this.body,
    this.tooltip,
  });

  final IconData icon;
  final String text;
  final Widget body;

  /// Hover label when [text] is abbreviated or may ellipsize.
  final String? tooltip;
}

/// Fluent `TabView` wrapper for consistent tabbed surfaces (settings, dashboard).
///
/// When there is only one item, the tab strip is omitted and the body is shown
/// directly to avoid a redundant single tab.
///
/// Section tabs are not documents: close buttons stay hidden (`onClosed` is
/// null) and browser-style shortcuts stay off so host pages keep Ctrl+T / Ctrl+W.
/// Labels size to content, ellipsize, and the strip scrolls when they no longer
/// fit, including four tabs at the main window minimum width.
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
      shortcutsEnabled: false,
      tabWidthBehavior: TabWidthBehavior.sizeToContent,
      closeButtonVisibility: CloseButtonVisibilityMode.never,
      tabs: items
          .map(
            (item) => Tab(
              icon: Icon(item.icon),
              semanticLabel: item.text,
              text: _tabLabel(item),
              body: item.body,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _tabLabel(AppFluentTabItem item) {
    final label = Text(
      item.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final tooltip = item.tooltip;
    if (tooltip == null || tooltip == item.text) {
      return label;
    }
    return Tooltip(message: tooltip, child: label);
  }
}

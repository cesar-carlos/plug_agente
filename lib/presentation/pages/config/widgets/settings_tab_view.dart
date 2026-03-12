import 'package:fluent_ui/fluent_ui.dart';

class SettingsTabItem {
  const SettingsTabItem({
    required this.icon,
    required this.text,
    required this.body,
  });

  final IconData icon;
  final String text;
  final Widget body;
}

class SettingsTabView extends StatelessWidget {
  const SettingsTabView({
    required this.currentIndex,
    required this.onChanged,
    required this.items,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<SettingsTabItem> items;

  @override
  Widget build(BuildContext context) {
    return TabView(
      currentIndex: currentIndex,
      onChanged: onChanged,
      tabs: items
          .map(
            (item) => Tab(
              icon: Icon(item.icon),
              text: Text(item.text),
              body: item.body,
            ),
          )
          .toList(growable: false),
    );
  }
}

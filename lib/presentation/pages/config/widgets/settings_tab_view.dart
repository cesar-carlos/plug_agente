import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Item for [SettingsTabView] (icon, label, body).
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

/// Padrão visual de abas em telas de configurações: Fluent `TabView` (faixa
/// nativa + corpo com page view). Use este widget para manter identidade
/// consistente com o restante do app (ex.: configurações da base de dados).
///
/// Quando há apenas um item, a faixa de abas é omitida e o corpo é renderizado
/// diretamente para evitar UI confusa (uma aba sozinha não traz informação).
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
    if (items.length <= 1) {
      if (items.isEmpty) {
        return const SizedBox.shrink();
      }
      return KeyedSubtree(
        key: const ValueKey('settings_tab_view_single'),
        child: items.first.body,
      );
    }
    return TabView(
      currentIndex: currentIndex,
      onChanged: onChanged,
      minTabWidth: 180,
      tabs: items
          .map(
            (SettingsTabItem item) => Tab(
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

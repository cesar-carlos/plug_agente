import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// One step of [AppPagedView].
class AppPageItem {
  const AppPageItem({
    required this.id,
    required this.label,
    required this.body,
    this.tooltip,
    this.summary,
    this.sectionKey,
  });

  final String id;
  final String label;
  final String? tooltip;
  final String? summary;
  final Widget body;
  final Key? sectionKey;
}

/// Shows one page at a time, with a wrapping tab strip and a shared footer.
///
/// Every page stays mounted. Form fields on the other steps keep their
/// controllers, and a horizontal drag moves between steps the same way a
/// [PageView] does.
class AppPagedView extends StatelessWidget {
  const AppPagedView({
    required this.pages,
    required this.currentIndex,
    required this.onPageChanged,
    this.scrollController,
    this.footer,
    super.key,
  });

  final List<AppPageItem> pages;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  /// Scroll controller of the page that is currently shown.
  final ScrollController? scrollController;

  /// Trailing actions rendered on the same row as previous/next, such as save.
  final Widget? footer;

  int _clampedIndex(int index) {
    if (pages.isEmpty) return 0;
    return index.clamp(0, pages.length - 1);
  }

  void _selectPage(int index) {
    final target = _clampedIndex(index);
    if (target == currentIndex) return;
    onPageChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final index = _clampedIndex(currentIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppPageStrip(
          pages: pages,
          currentIndex: index,
          onSelect: _selectPage,
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity <= -200) _selectPage(index + 1);
              if (velocity >= 200) _selectPage(index - 1);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var pageIndex = 0; pageIndex < pages.length; pageIndex++)
                  Visibility(
                    visible: pageIndex == index,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    maintainFocusability: true,
                    child: _AppPageBody(
                      page: pages[pageIndex],
                      scrollController: pageIndex == index ? scrollController : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        _AppPageFooter(
          l10n: l10n,
          index: index,
          pageCount: pages.length,
          onSelect: _selectPage,
          trailing: footer,
        ),
      ],
    );
  }
}

class _AppPageStrip extends StatelessWidget {
  const _AppPageStrip({
    required this.pages,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<AppPageItem> pages;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.appColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var pageIndex = 0; pageIndex < pages.length; pageIndex++)
              _AppPageTab(
                page: pages[pageIndex],
                selected: pageIndex == currentIndex,
                onPressed: () => onSelect(pageIndex),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppPageTab extends StatelessWidget {
  const _AppPageTab({
    required this.page,
    required this.selected,
    required this.onPressed,
  });

  final AppPageItem page;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tooltip = page.tooltip ?? page.label;
    return Semantics(
      key: ValueKey('app_page_${page.id}'),
      button: true,
      selected: selected,
      label: page.label,
      child: Tooltip(
        message: tooltip,
        child: HoverButton(
          onPressed: onPressed,
          cursor: SystemMouseCursors.click,
          builder: (context, states) {
            final hovered = states.isHovered || states.isPressed;
            return FocusBorder(
              focused: states.isFocused,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? colors.selectedFill
                      : hovered
                      ? FluentTheme.of(context).resources.subtleFillColorSecondary
                      : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sm)),
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? colors.brand : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Text(
                    page.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: selected ? context.bodyStrong.copyWith(color: colors.selectedForeground) : context.bodyText,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppPageFooter extends StatelessWidget {
  const _AppPageFooter({
    required this.l10n,
    required this.index,
    required this.pageCount,
    required this.onSelect,
    required this.trailing,
  });

  final AppLocalizations l10n;
  final int index;
  final int pageCount;
  final ValueChanged<int> onSelect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final showNavigation = pageCount > 1;
    if (!showNavigation && trailing == null) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.appColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (showNavigation)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    onPressed: index > 0 ? () => onSelect(index - 1) : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.chevron_left, size: 12),
                        const SizedBox(width: AppSpacing.xs),
                        Text(l10n.pagedViewPrevious),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Button(
                    onPressed: index < pageCount - 1 ? () => onSelect(index + 1) : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.pagedViewNext),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(FluentIcons.chevron_right, size: 12),
                      ],
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: l10n.pagedViewPosition(index + 1, pageCount),
                    child: const SizedBox.shrink(),
                  ),
                ],
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _AppPageBody extends StatelessWidget {
  const _AppPageBody({
    required this.page,
    required this.scrollController,
  });

  final AppPageItem page;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      controller: scrollController,
      primary: false,
      padding: const EdgeInsets.only(right: AppLayout.scrollbarPadding, bottom: AppSpacing.md),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (page.summary != null) ...[
              Text(page.summary!, style: context.captionText),
              const SizedBox(height: AppSpacing.sm),
            ],
            page.body,
          ],
        ),
      ),
    );

    return KeyedSubtree(
      key: page.sectionKey ?? ValueKey('app_page_body_${page.id}'),
      child: scrollController == null
          ? scrollView
          : Scrollbar(
              controller: scrollController,
              child: scrollView,
            ),
    );
  }
}

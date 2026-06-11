import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class ClientTokenListFilters extends StatelessWidget {
  const ClientTokenListFilters({
    required this.clientFilterController,
    required this.tokenStatusFilter,
    required this.tokenSortOption,
    required this.isEnabled,
    required this.onClientFilterChanged,
    required this.statusLabelBuilder,
    required this.sortLabelBuilder,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onClearFilters,
    super.key,
  });

  final TextEditingController clientFilterController;
  final ClientTokenStatusFilter tokenStatusFilter;
  final ClientTokenSortOption tokenSortOption;
  final bool isEnabled;
  final ValueChanged<String> onClientFilterChanged;
  final String Function(ClientTokenStatusFilter) statusLabelBuilder;
  final String Function(ClientTokenSortOption) sortLabelBuilder;
  final ValueChanged<ClientTokenStatusFilter> onStatusChanged;
  final ValueChanged<ClientTokenSortOption> onSortChanged;
  final VoidCallback onClearFilters;

  static const double compactBreakpoint = 980;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clientFilterField = AppTextField(
      label: l10n.ctFilterClientId,
      controller: clientFilterController,
      hint: l10n.ctHintClientId,
      enabled: isEnabled,
      onChanged: isEnabled ? onClientFilterChanged : null,
    );
    final statusField = AppDropdown<ClientTokenStatusFilter>(
      label: l10n.ctFilterStatus,
      value: tokenStatusFilter,
      items: ClientTokenStatusFilter.values
          .map(
            (item) => ComboBoxItem<ClientTokenStatusFilter>(
              value: item,
              child: Text(statusLabelBuilder(item)),
            ),
          )
          .toList(),
      onChanged: isEnabled
          ? (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            }
          : null,
    );
    final sortField = AppDropdown<ClientTokenSortOption>(
      label: l10n.ctFilterSort,
      value: tokenSortOption,
      items: ClientTokenSortOption.values
          .map(
            (item) => ComboBoxItem<ClientTokenSortOption>(
              value: item,
              child: Text(sortLabelBuilder(item)),
            ),
          )
          .toList(),
      onChanged: isEnabled
          ? (value) {
              if (value != null) {
                onSortChanged(value);
              }
            }
          : null,
    );
    final clearFiltersButton = AppButton(
      label: l10n.ctButtonClearFilters,
      isPrimary: false,
      icon: FluentIcons.clear_filter,
      onPressed: isEnabled ? onClearFilters : null,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              clientFilterField,
              const SizedBox(height: AppSpacing.md),
              statusField,
              const SizedBox(height: AppSpacing.md),
              sortField,
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: clearFiltersButton,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 3, child: clientFilterField),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: statusField),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: sortField),
            const SizedBox(width: AppSpacing.md),
            clearFiltersButton,
          ],
        );
      },
    );
  }
}

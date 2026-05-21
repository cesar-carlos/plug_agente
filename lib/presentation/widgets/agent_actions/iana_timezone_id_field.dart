import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:timezone/timezone.dart' as tz;

/// Searchable IANA time zone picker for daily / weekly / monthly triggers.
class IanaTimezoneIdField extends StatefulWidget {
  const IanaTimezoneIdField({
    required this.controller,
    required this.enabled,
    required this.l10n,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final AppLocalizations l10n;

  @override
  State<IanaTimezoneIdField> createState() => _IanaTimezoneIdFieldState();
}

class _IanaTimezoneIdFieldState extends State<IanaTimezoneIdField> {
  static const int _maxMatches = 400;

  late final List<String> _allIds;
  late final TextEditingController _filterController;

  @override
  void initState() {
    super.initState();
    ensureIanaTimeZoneDataLoaded();
    _allIds = tz.timeZoneDatabase.locations.keys.toList()..sort();
    _filterController = TextEditingController();
    _filterController.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    super.dispose();
  }

  ({List<String> matches, bool truncated}) _matchesAndTruncation() {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return (matches: const <String>[], truncated: false);
    }

    final buffer = <String>[];
    var truncated = false;
    for (final id in _allIds) {
      if (!id.toLowerCase().contains(query)) {
        continue;
      }
      if (buffer.length >= _maxMatches) {
        truncated = true;
        break;
      }
      buffer.add(id);
    }

    return (matches: buffer, truncated: truncated);
  }

  void _selectId(String id) {
    widget.controller.text = id;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final result = _matchesAndTruncation();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppTextField(
          controller: widget.controller,
          label: l10n.agentActionsTriggerFieldTimezone,
          enabled: widget.enabled,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _filterController,
          label: l10n.agentActionsTriggerFieldTimezoneFilter,
          hint: l10n.agentActionsTriggerHintTimezoneFilter,
          enabled: widget.enabled,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.agentActionsTriggerHintTimezonePick, style: context.captionText),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 200,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: FluentTheme.of(context).resources.controlStrokeColorDefault),
              borderRadius: BorderRadius.circular(4),
            ),
            child: result.matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        _filterController.text.trim().isEmpty
                            ? l10n.agentActionsTriggerHintTimezoneSearchEmpty
                            : l10n.agentActionsTriggerTimezoneNoMatches,
                        style: context.bodyText,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: result.matches.length,
                    itemBuilder: (context, index) {
                      final id = result.matches[index];
                      return ListTile.selectable(
                        title: Text(id),
                        selected: widget.controller.text.trim() == id,
                        onPressed: widget.enabled ? () => _selectId(id) : null,
                      );
                    },
                  ),
          ),
        ),
        if (result.truncated) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsTriggerTimezoneMatchesTruncated(_maxMatches),
            style: context.captionText,
          ),
        ],
      ],
    );
  }
}

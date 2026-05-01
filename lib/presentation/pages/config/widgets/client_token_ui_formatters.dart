import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

String formatClientTokenDateTime(BuildContext context, DateTime value) {
  final localeName = Localizations.localeOf(context).toString();
  return DateFormat.yMd(localeName).add_Hm().format(value.toLocal());
}

String localizeClientTokenRuleType(AppLocalizations l10n, DatabaseResourceType type) {
  return switch (type) {
    DatabaseResourceType.table => l10n.ctRuleTypeTable,
    DatabaseResourceType.view => l10n.ctRuleTypeView,
    DatabaseResourceType.unknown => l10n.ctRuleTypeUnknown,
  };
}

String localizeClientTokenRuleEffect(AppLocalizations l10n, ClientTokenRuleEffect effect) {
  return switch (effect) {
    ClientTokenRuleEffect.allow => l10n.ctRuleEffectAllow,
    ClientTokenRuleEffect.deny => l10n.ctRuleEffectDeny,
  };
}

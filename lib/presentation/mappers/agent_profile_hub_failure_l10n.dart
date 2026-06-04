import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/mappers/hub_auth_failure_l10n.dart';

extension AgentProfileHubFailureL10n on Object {
  String toAgentProfileHubDisplayMessage(AppLocalizations l10n) {
    final failure = asFailure;
    if (failure is ProfileVersionConflictFailure) {
      return failure.message;
    }
    if (failure != null && isHubSessionAuthFailure(failure)) {
      return hubAuthFailureDisplayMessage(failure, l10n);
    }
    return toDisplayMessage();
  }
}

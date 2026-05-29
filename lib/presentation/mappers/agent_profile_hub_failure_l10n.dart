import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

extension AgentProfileHubFailureL10n on Object {
  String toAgentProfileHubDisplayMessage(AppLocalizations l10n) {
    final failure = asFailure;
    if (failure is ProfileVersionConflictFailure) {
      return failure.message;
    }
    return toDisplayMessage();
  }
}

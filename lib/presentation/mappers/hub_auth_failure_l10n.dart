import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

bool isHubSessionAuthFailure(Failure failure) {
  final statusCode = failure.context['statusCode'];
  if (statusCode == AppConstants.httpStatusUnauthorized) {
    return true;
  }
  final message = failure.message.toLowerCase();
  return message.contains('jwt expired') ||
      message.contains('session expired') ||
      message.contains('unauthorized');
}

String hubAuthFailureDisplayMessage(Failure failure, AppLocalizations l10n) {
  if (isHubSessionAuthFailure(failure)) {
    return l10n.hubSessionExpiredSignInAgain;
  }
  return failure.message;
}

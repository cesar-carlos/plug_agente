import 'package:flutter/widgets.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Extensions for failure display with localized messages.
extension FailureLocalizationExtension on Object {
  /// Returns localized display message when [context] and AppLocalizations
  /// are available and the failure has a known ODBC reason.
  String toDisplayMessageLocalized(BuildContext context) {
    if (this is! Failure) return toDisplayMessage();

    final failure = this as Failure;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return toDisplayMessage();

    final reason = failure.context['reason'] as String?;
    if (reason == null) return toDisplayMessage();

    final localized = _resolveOdbcReason(l10n, reason);
    if (localized != null) return localized;

    return toDisplayMessage();
  }

  /// Returns localized display message with ODBC detail when available.
  String toDisplayMessageWithOdbcDetailLocalized(BuildContext context) {
    final base = toDisplayMessageLocalized(context);
    if (this is! Failure) return base;

    final failure = this as Failure;
    final odbcMessage = failure.context['odbc_message'] as String?;
    if (odbcMessage == null || odbcMessage.trim().isEmpty) return base;

    final l10n = AppLocalizations.of(context);
    final prefix = l10n?.odbcDetailPrefix ?? 'Detalhe ODBC';

    return '$base\n\n$prefix: $odbcMessage';
  }

  static String? _resolveOdbcReason(AppLocalizations l10n, String reason) {
    return switch (reason) {
      'odbc_driver_not_found' => l10n.odbcDriverNotFound,
      'authentication_failed' => l10n.odbcAuthFailed,
      'server_unreachable' => l10n.odbcServerUnreachable,
      'connection_timeout' => l10n.odbcConnectionTimeout,
      'database_connection_failed' => l10n.odbcConnectionFailed,
      _ => null,
    };
  }
}

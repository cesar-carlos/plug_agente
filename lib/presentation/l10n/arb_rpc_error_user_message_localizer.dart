import 'package:plug_agente/domain/protocol/rpc_error_user_message_localizer.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// AppLocalizations-backed implementation of [RpcErrorUserMessageLocalizer].
///
/// Install at boot via:
/// ```dart
/// RpcErrorCode.userMessageLocalizer = ArbRpcErrorUserMessageLocalizer(l10n);
/// ```
/// The bound instance is single-locale (whichever AppLocalizations was created
/// for the current MaterialApp). Re-install on locale change to update the
/// strings emitted on the wire.
class ArbRpcErrorUserMessageLocalizer implements RpcErrorUserMessageLocalizer {
  const ArbRpcErrorUserMessageLocalizer(this._l10n);

  final AppLocalizations _l10n;

  @override
  String invalidRequest() => _l10n.msgRpcInvalidRequest;

  @override
  String methodNotFound() => _l10n.msgRpcMethodNotFound;

  @override
  String authenticationFailed() => _l10n.msgRpcAuthenticationFailed;

  @override
  String unauthorized() => _l10n.msgRpcUnauthorized;

  @override
  String timeout() => _l10n.msgRpcTimeout;

  @override
  String invalidPayload() => _l10n.msgRpcInvalidPayload;

  @override
  String networkError() => _l10n.msgRpcNetworkError;

  @override
  String rateLimited() => _l10n.msgRpcRateLimited;

  @override
  String replayDetected() => _l10n.msgRpcReplayDetected;

  @override
  String sqlValidationFailed() => _l10n.msgRpcSqlValidationFailed;

  @override
  String sqlExecutionFailed() => _l10n.msgRpcSqlExecutionFailed;

  @override
  String connectionPoolExhausted() => _l10n.msgRpcConnectionPoolExhausted;

  @override
  String resultTooLarge() => _l10n.msgRpcResultTooLarge;

  @override
  String databaseConnectionFailed() => _l10n.msgRpcDatabaseConnectionFailed;

  @override
  String invalidDatabaseConfig() => _l10n.msgRpcInvalidDatabaseConfig;

  @override
  String executionNotFound() => _l10n.msgRpcExecutionNotFound;

  @override
  String executionCancelled() => _l10n.msgRpcExecutionCancelled;

  @override
  String internalError() => _l10n.msgRpcInternalError;
}

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

/// True when a mapped failure means the ODBC session is no longer usable.
abstract final class OdbcLostSessionFailure {
  static bool matches(domain.Failure failure) {
    if (failure.context['connectionFailed'] != true) {
      return false;
    }
    final reason = failure.context['reason'];
    return reason == OdbcContextConstants.connectionLostDuringQueryReason ||
        reason == OdbcContextConstants.odbcWorkerCrashedReason;
  }
}

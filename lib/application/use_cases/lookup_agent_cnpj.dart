import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Use case that sanitizes the raw input, ensures it has the expected CNPJ
/// length and delegates the actual remote lookup to the gateway.
///
/// Keeping the digit-length policy here removes a presentation responsibility
/// and lets the page focus on rendering and feedback.
class LookupAgentCnpj {
  LookupAgentCnpj(this._gateway);

  final IOpenCnpjLookup _gateway;

  static const int _expectedCnpjLength = 14;
  static final RegExp _nonDigits = RegExp('[^0-9]');

  Future<Result<OpenCnpjCompanyData>> call({
    required String rawDocument,
    required String invalidLengthMessage,
    required OpenCnpjLookupErrorMessages errorMessages,
  }) {
    final digits = rawDocument.replaceAll(_nonDigits, '');
    if (digits.length != _expectedCnpjLength) {
      return Future.value(
        Failure(domain.ValidationFailure(invalidLengthMessage)),
      );
    }

    return _gateway.lookupCnpj(digits, errorMessages: errorMessages);
  }
}

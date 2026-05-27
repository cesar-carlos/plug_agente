import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Use case that sanitizes the raw input, ensures it has the expected CEP
/// length and delegates the actual remote lookup to the gateway.
class LookupAgentCep {
  LookupAgentCep(this._gateway);

  final IViaCepLookup _gateway;

  static const int _expectedCepLength = 8;
  static final RegExp _nonDigits = RegExp('[^0-9]');

  Future<Result<ViaCepAddress>> call({
    required String rawPostalCode,
    required String invalidLengthMessage,
  }) {
    final digits = rawPostalCode.replaceAll(_nonDigits, '');
    if (digits.length != _expectedCepLength) {
      return Future.value(
        Failure(domain.ValidationFailure(invalidLengthMessage)),
      );
    }

    return _gateway.lookupCep(digits);
  }
}

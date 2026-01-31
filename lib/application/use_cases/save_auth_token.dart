import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:result_dart/result_dart.dart';

class SaveAuthToken {
  SaveAuthToken(this._service);
  final AuthService _service;

  Future<Result<void>> call(AuthToken token) async {
    return _service.saveAuthToken(token);
  }
}

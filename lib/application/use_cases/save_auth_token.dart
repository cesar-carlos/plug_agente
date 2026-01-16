import 'package:result_dart/result_dart.dart';

import '../../domain/entities/auth_token.dart';
import '../services/auth_service.dart';

class SaveAuthToken {
  final AuthService _service;

  SaveAuthToken(this._service);

  Future<Result<void>> call(AuthToken token) async {
    return await _service.saveAuthToken(token);
  }
}

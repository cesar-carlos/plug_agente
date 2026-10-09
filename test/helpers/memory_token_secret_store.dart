import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class MemoryTokenSecretStore implements ITokenSecretStore {
  final Map<String, String> values = {};
  bool available = true;
  bool failWrite = false;
  bool failRead = false;
  bool unconfirmed = false;
  int reads = 0;
  Future<void> Function()? beforeWrite;

  @override
  bool get isAvailable => available;
  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {
    if (beforeWrite != null) await beforeWrite!();
    if (failWrite) throw Exception('injected secure storage failure');
    values[secretKey] = tokenValue;
  }

  @override
  Future<String?> readSecret(String secretKey) async {
    reads++;
    if (failRead) throw Exception('injected secure read failure');
    return unconfirmed ? null : values[secretKey];
  }

  @override
  Future<void> deleteSecret(String secretKey) async {
    values.remove(secretKey);
  }
}

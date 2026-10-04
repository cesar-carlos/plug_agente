import 'package:result_dart/result_dart.dart';

abstract interface class IUpdateSecretsSnapshot {
  Future<Result<String>> captureEncrypted();
  Future<Result<void>> restoreEncrypted(String encryptedBlob);
}

/// The exact rollback namespace differs deliberately from portable backup.
const updateSecretNamespaces = <String>[
  'odbc_credential_secret_',
  'hub_auth_secret_',
  'client_token_secret_',
  'agent_action_secret_',
  'payload_signing_',
];

bool isUpdateSecretKey(String key) => updateSecretNamespaces.any(key.startsWith);

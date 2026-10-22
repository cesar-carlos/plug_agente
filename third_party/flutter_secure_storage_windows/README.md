# Windows secure-storage backend: local correction

Based on flutter_secure_storage_windows 4.2.2 (mogol/flutter_secure_storage).
The upstream LICENSE is retained. This is a modified local dependency, not an
upstream release; pubspec.yaml pins the application to this directory.

Changes are confined to the Dart Windows backend:
- All platform operations acquire an exclusive file lock in the same support
  directory before reading/modifying the encrypted map. Contention is bounded
  to ten seconds; only Windows sharing/lock violations are retried.
- DPAPI ciphertext is flushed to a uniquely named sibling file, then replaced
  with MoveFileExW REPLACE_EXISTING | WRITE_THROUGH. The current file is never
  truncated during a normal write. An orphan .next file is not loaded/promoted.
- Read, decrypt and JSON errors propagate without deleting the stored file or
  silently treating unreadable content as an empty vault.
- The existing DPAPI format, filename, keys and legacy interface are preserved.

The lock must remain present; never delete its pathname while another process
may hold it. Old executables which do not acquire this lock cannot safely run
concurrently with this build. Stop all vault users before a coordinated upgrade.
This does not make multiple credential keys a database transaction, certify
power-loss durability or implement cleanup of encrypted orphan temporary files.

Regression runner is in plug_mcp/scripts/homologation/probe-persona-agent-vault.ps1;
it uses only generated synthetic credentials in a temporary private vault.
Do not test against installed/operational storage or edit the global Pub cache.

/// Records the last legacy SQLite database migration outcome for health/diagnostics.
abstract final class LegacyDatabaseMigrationStatus {
  static String? lastFailureMessage;

  static void recordFailure(String message) {
    lastFailureMessage = message;
  }

  static void clear() {
    lastFailureMessage = null;
  }
}

class SqlValidCommand {
  static void validateConnection(bool isConnected) {
    if (!isConnected) {
      throw Exception('Conexão não estabelecida. Chame connect() primeiro.');
    }
  }

  static void validateCommandText(String? commandText) {
    if (commandText == null || commandText.isEmpty) {
      throw Exception('commandText não pode ser vazio.');
    }
  }

  static void validateForOpen(String commandText) {
    if (isSelectQuery(commandText)) {
      return;
    }

    final normalizedQuery = commandText.trim().toUpperCase();
    if (normalizedQuery.startsWith('INSERT') ||
        normalizedQuery.startsWith('UPDATE') ||
        normalizedQuery.startsWith('DELETE')) {
      throw Exception(
          'open() não permite INSERT, UPDATE ou DELETE. Use execute() para essas operações.');
    }

    throw Exception(
        'open() é apenas para operações SELECT. Use execute() para INSERT, UPDATE, DELETE.');
  }

  static void validateForExecute(String commandText) {
    if (isSelectQuery(commandText)) {
      throw Exception(
          'Use open() para operações SELECT. execute() é para INSERT, UPDATE, DELETE.');
    }
  }

  static bool isSelectQuery(String query) {
    final normalizedQuery = query.trim().toUpperCase();
    return normalizedQuery.startsWith('SELECT');
  }

  static void validateOpen(bool isConnected, String? commandText) {
    validateConnection(isConnected);
    validateCommandText(commandText);
    if (commandText != null) {
      validateForOpen(commandText);
    }
  }

  static void validateExecute(bool isConnected, String? commandText) {
    validateConnection(isConnected);
    validateCommandText(commandText);
    if (commandText != null) {
      validateForExecute(commandText);
    }
  }
}

/// Application UI string constants.
///
/// Centralizes all user-facing strings to maintain consistency
/// and facilitate future localization efforts.
class AppStrings {
  AppStrings._();

  // Navigation
  static const String navDashboard = 'Dashboard';
  static const String navPlayground = 'Playground';
  static const String navSettings = 'Configurações';

  // Page Titles
  static const String titlePlayground = 'Playground Database';
  static const String titleConfig = 'Configurações - Plug Database';

  // Modal Titles
  static const String modalTitleSuccess = 'Sucesso';
  static const String modalTitleError = 'Erro';
  static const String modalTitleAuthError = 'Erro de Autenticação';
  static const String modalTitleConnectionError = 'Erro de Conexão';
  static const String modalTitleConfigError = 'Erro de Configuração';
  static const String modalTitleConnectionEstablished = 'Conexão Estabelecida';
  static const String modalTitleDriverNotFound = 'Driver Não Encontrado';
  static const String modalTitleConnectionSuccessful = 'Conexão Bem-Sucedida';
  static const String modalTitleConnectionFailed = 'Falha na Conexão';
  static const String modalTitleConfigSaved = 'Configuração Salva';
  static const String modalTitleErrorTestingConnection =
      'Erro ao Testar Conexão';
  static const String modalTitleErrorVerifyingDriver =
      'Erro ao Verificar Driver';
  static const String modalTitleErrorSaving = 'Erro ao Salvar';
  static const String modalTitleConnectionStatus = 'Status da Conexão';

  // Success Messages
  static const String msgAuthenticatedSuccessfully = 'Autenticado com sucesso!';
  static const String msgWebSocketConnectedSuccessfully =
      'Conectado ao servidor WebSocket com sucesso!';
  static const String msgDatabaseConnectionSuccessful =
      'Conexão com o banco de dados estabelecida com sucesso!';
  static const String msgConfigSavedSuccessfully =
      'Configuração salva com sucesso!';
  static const String msgConnectionSuccessful = 'sucesso';

  // Error Messages
  static const String msgOdbcDriverNameRequired =
      'Nome do Driver ODBC é obrigatório';

  /// Returns driver not found message with the driver name.
  static String driverNotFound(String driverName) =>
      'Driver ODBC "$driverName" não foi encontrado. '
      'Verifique se o driver está instalado antes de {action}.';

  /// Returns driver not found message for connection test.
  static String driverNotFoundForTest(String driverName) =>
      driverNotFound(driverName).replaceFirst('{action}', 'testar a conexão');

  /// Returns driver not found message for save config.
  static String driverNotFoundForSave(String driverName) => driverNotFound(
    driverName,
  ).replaceFirst('{action}', 'salvar a configuração');

  // Connection Messages
  static const String msgConnectionCheckFailed =
      'Não foi possível conectar ao banco de dados. Verifique as credenciais e configurações.';

  // Button Labels
  static const String btnOk = 'OK';
  static const String btnCancel = 'Cancelar';

  // Query Results
  static const String queryNoResults = 'Sem resultados';
  static const String queryNoResultsMessage =
      'Execute uma consulta SELECT para ver os resultados aqui.';
  static const String queryErrorTitle = 'Erro na Consulta';
  static const String queryErrorShowDetails = 'Ver Detalhes';
  static const String queryTotalRecords = 'Total de registros';
  static const String queryExecutionTime = 'Tempo de execução';
  static const String queryAffectedRows = 'Linhas afetadas';

  // Dashboard
  static const String dashboardDescription =
      'Monitor your agent status and database connections here.';
}

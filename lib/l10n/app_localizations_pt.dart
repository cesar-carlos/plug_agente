// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navDatabaseSettings => 'Banco de dados';

  @override
  String get navPlayground => 'Playground';

  @override
  String get navSettings => 'Configurações';

  @override
  String get navWebSocketSettings => 'Conexão WebSocket';

  @override
  String get mainDegradedModeTitle => 'Modo Degradado Ativo';

  @override
  String get mainDegradedModeDescription =>
      'O aplicativo está rodando com recursos limitados:';

  @override
  String get titlePlayground => 'Playground Database';

  @override
  String get titleConfig => 'Configurações - Plug Database';

  @override
  String get modalTitleSuccess => 'Sucesso';

  @override
  String get modalTitleError => 'Erro';

  @override
  String get modalTitleAuthError => 'Erro de Autenticação';

  @override
  String get modalTitleConnectionError => 'Erro de Conexão';

  @override
  String get modalTitleConfigError => 'Erro de Configuração';

  @override
  String get modalTitleConnectionEstablished => 'Conexão Estabelecida';

  @override
  String get modalTitleDriverNotFound => 'Driver Não Encontrado';

  @override
  String get modalTitleConnectionSuccessful => 'Conexão Bem-Sucedida';

  @override
  String get modalTitleConnectionFailed => 'Falha na Conexão';

  @override
  String get modalTitleConfigSaved => 'Configuração Salva';

  @override
  String get modalTitleErrorTestingConnection => 'Erro ao Testar Conexão';

  @override
  String get modalTitleErrorVerifyingDriver => 'Erro ao Verificar Driver';

  @override
  String get modalTitleErrorSaving => 'Erro ao Salvar';

  @override
  String get modalTitleConnectionStatus => 'Status da Conexão';

  @override
  String get msgAuthenticatedSuccessfully => 'Autenticado com sucesso!';

  @override
  String get msgWebSocketConnectedSuccessfully =>
      'Conectado ao servidor WebSocket com sucesso!';

  @override
  String get msgDatabaseConnectionSuccessful =>
      'Conexão com o banco de dados estabelecida com sucesso!';

  @override
  String get msgConfigSavedSuccessfully => 'Configuração salva com sucesso!';

  @override
  String get msgConnectionSuccessful => 'sucesso';

  @override
  String get msgOdbcDriverNameRequired => 'Nome do Driver ODBC é obrigatório';

  @override
  String get msgConnectionCheckFailed =>
      'Não foi possível conectar ao banco de dados. Verifique as credenciais e configurações.';

  @override
  String get btnOk => 'OK';

  @override
  String get btnCancel => 'Cancelar';

  @override
  String get btnRetry => 'Tentar novamente';

  @override
  String get errorTitleValidation => 'Dados inválidos';

  @override
  String get errorTitleNetwork => 'Erro de rede';

  @override
  String get errorTitleDatabase => 'Erro no banco de dados';

  @override
  String get errorTitleServer => 'Erro no servidor';

  @override
  String get errorTitleNotFound => 'Não encontrado';

  @override
  String get queryNoResults => 'Sem resultados';

  @override
  String get queryNoResultsMessage =>
      'Execute uma consulta SELECT para ver os resultados aqui.';

  @override
  String get queryTotalRecords => 'Total de registros';

  @override
  String get queryExecutionTime => 'Tempo de execução';

  @override
  String get queryAffectedRows => 'Linhas afetadas';

  @override
  String get queryErrorTitle => 'Erro na consulta';

  @override
  String get queryErrorShowDetails => 'Ver detalhes';

  @override
  String get querySqlLabel => 'Consulta SQL';

  @override
  String get querySqlHint => 'SELECT * FROM tabela...';

  @override
  String get queryActionExecute => 'Executar';

  @override
  String get queryActionTestConnection => 'Testar conexão';

  @override
  String get queryActionClear => 'Limpar';

  @override
  String get queryActionCancel => 'Cancelar';

  @override
  String get queryConnectionStatusTitle => 'Status da conexão';

  @override
  String get queryConnectionTesting => 'Testando conexão...';

  @override
  String get queryConnectionSuccess => 'Conexão estabelecida com sucesso';

  @override
  String get queryConnectionFailure => 'Falha na conexão';

  @override
  String get queryCancelledByUser => 'Consulta cancelada pelo usuário';

  @override
  String get queryStreamingErrorPrefix => 'Erro no streaming';

  @override
  String get queryStreamingMode => 'Modo streaming';

  @override
  String get querySqlHandlingModePreserve => 'Preservar SQL';

  @override
  String get querySqlHandlingModePreserveHint =>
      'Executa a SQL exatamente como enviada, sem reescrita de paginação';

  @override
  String get queryPlaygroundHintLastRunPreserve =>
      'Última execução: SQL preservada (sem reescrita de paginação pelo agente).';

  @override
  String get queryPlaygroundHintLastRunManagedPagination =>
      'Última execução: paginação gerenciada — a SQL pode ter sido reescrita para o dialeto do banco.';

  @override
  String get queryPlaygroundHintLastRunManaged =>
      'Última execução: modo gerenciado — limites e ajustes do agente podem aplicar-se à SQL.';

  @override
  String get queryPlaygroundHintLastRunStreaming =>
      'Última execução: modo streaming — resultados recebidos em fluxo contínuo.';

  @override
  String queryPlaygroundStreamingRowCapHint(int max) {
    return 'Exibição limitada a $max linhas no streaming (memória). A consulta no servidor foi interrompida ao atingir esse limite.';
  }

  @override
  String get queryStreamingModeHint =>
      'Para grandes datasets (milhares de linhas)';

  @override
  String get queryStreamingProgress => 'Processando';

  @override
  String get queryStreamingRows => 'linhas';

  @override
  String get queryPaginationPage => 'Página';

  @override
  String get queryPaginationPageSize => 'Linhas por página';

  @override
  String get queryPaginationPrevious => 'Anterior';

  @override
  String get queryPaginationNext => 'Próxima';

  @override
  String get queryPaginationShowing => 'Exibindo';

  @override
  String get queryResultSetLabel => 'Conjunto de resultados';

  @override
  String get queryExecuteGenericError => 'Erro ao executar a consulta';

  @override
  String get dashboardDescription =>
      'Monitore o status do seu agente e conexões de banco de dados aqui.';

  @override
  String get connectionStatusConnected => 'Conectado';

  @override
  String get connectionStatusConnecting => 'Conectando...';

  @override
  String get connectionStatusError => 'Erro de conexão';

  @override
  String get connectionStatusDisconnected => 'Desconectado';

  @override
  String get connectionStatusDbConnected => 'BD: conectado';

  @override
  String get connectionStatusDbDisconnected => 'BD: desconectado';

  @override
  String get dashboardMetricsTitle => 'Métricas ODBC';

  @override
  String get dashboardMetricsQueries => 'Queries executadas';

  @override
  String get dashboardMetricsSuccess => 'Sucesso';

  @override
  String get dashboardMetricsErrors => 'Erros';

  @override
  String get dashboardMetricsSuccessRate => 'Taxa de sucesso';

  @override
  String get dashboardMetricsAvgLatency => 'Latência média';

  @override
  String get dashboardMetricsMaxLatency => 'Latência máxima';

  @override
  String get dashboardMetricsTotalRows => 'Total de linhas';

  @override
  String get dashboardMetricsPeriod => 'Período';

  @override
  String get dashboardMetricsPeriod1h => 'Última 1h';

  @override
  String get dashboardMetricsPeriod24h => 'Últimas 24h';

  @override
  String get dashboardMetricsPeriodAll => 'Total';

  @override
  String get wsLogTitle => 'Mensagens WebSocket';

  @override
  String get wsLogEnabled => 'Ativo';

  @override
  String get wsLogClear => 'Limpar';

  @override
  String get wsLogNoMessages => 'Ainda sem mensagens';

  @override
  String get wsLogAuthChecks => 'Verificações de auth';

  @override
  String get wsLogAllowed => 'Permitidas';

  @override
  String get wsLogDenied => 'Negadas';

  @override
  String get wsLogDenialRate => 'Taxa de negação';

  @override
  String get wsLogP95Latency => 'Latência P95 (auth)';

  @override
  String get wsLogP99Latency => 'Latência P99 (auth)';

  @override
  String get wsLogPreserveSqlDeprecatedUses =>
      'Uso de preserve_sql (deprecated)';

  @override
  String get odbcDriverNotFound =>
      'O driver ODBC configurado não foi encontrado neste computador. Revise o driver e a fonte de dados nas configurações.';

  @override
  String get odbcAuthFailed =>
      'Não foi possível autenticar no banco de dados. Verifique usuário, senha e permissões.';

  @override
  String get odbcServerUnreachable =>
      'Não foi possível conectar ao servidor do banco. Verifique host, porta, VPN e disponibilidade da rede.';

  @override
  String get odbcConnectionTimeout =>
      'A conexão com o banco demorou mais do que o esperado. Confirme se o servidor está acessível e tente novamente.';

  @override
  String get odbcConnectionFailed =>
      'Não foi possível estabelecer conexão com o banco de dados.';

  @override
  String get odbcDetailPrefix => 'Detalhe ODBC';
}

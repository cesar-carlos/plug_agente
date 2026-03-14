/// Application UI string constants.
///
/// Centralizes all user-facing strings to maintain consistency
/// and facilitate future localization efforts.
class AppStrings {
  AppStrings._();

  // Navigation
  static const String navDashboard = 'Dashboard';
  static const String navPlayground = 'Playground';
  static const String navWebSocketSettings = 'Conexão WebSocket';
  static const String tabWebSocketConnection = 'Conexão WebSocket';
  static const String tabClientTokenAuthorization =
      'Autorização de Token do Cliente';
  static const String navSettings = 'Configurações';
  static const String navDatabaseSettings = 'Banco de dados';

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
  static const String msgServerUrlRequired = 'URL do Servidor é obrigatória';
  static const String msgAuthCredentialsRequired =
      'Usuário e senha são obrigatórios';

  // WebSocket Settings
  static const String wsSectionConnection = 'Conexão WebSocket';
  static const String wsSectionOptionalAuth = 'Autenticação (Opcional)';
  static const String wsFieldServerUrl = 'URL do Servidor';
  static const String wsFieldAgentId = 'ID do Agente';
  static const String wsFieldUsername = 'Usuário';
  static const String wsHintServerUrl = 'https://api.example.com';
  static const String wsHintAgentId = 'UUID ou Nome Único';
  static const String wsHintUsername = 'Usuário para autenticação';
  static const String wsHintPassword = 'Senha para autenticação';
  static const String wsButtonAuthenticating = 'Autenticando...';
  static const String wsButtonLogout = 'Logout';
  static const String wsButtonLogin = 'Login';
  static const String wsButtonDisconnect = 'Desconectar';
  static const String wsButtonConnect = 'Conectar';
  static const String wsButtonSaveConfig = 'Salvar Configuração';

  // Client Token Settings
  static const String ctSectionTitle = 'Client Token Authorization';
  static const String ctFieldClientId = 'Client ID (gerado automaticamente)';
  static const String ctFieldAgentIdOptional = 'Agent ID (opcional)';
  static const String ctFieldPayloadJsonOptional = 'Payload JSON (opcional)';
  static const String ctHintClientId = 'Gerado automaticamente';
  static const String ctHintAgentId = 'agent-01';
  static const String ctHintPayloadJson =
      '{"display_name":"Acme ERP","env":"production"}';
  static const String ctFlagAllTables = 'all_tables';
  static const String ctFlagAllViews = 'all_views';
  static const String ctFlagAllPermissions = 'all_permissions';
  static const String ctSectionRulesByResource = 'Regras por recurso';
  static const String ctRuleTitlePrefix = 'Regra';
  static const String ctButtonAddRule = 'Adicionar regra';
  static const String ctButtonCreateToken = 'Criar token';
  static const String ctButtonNewToken = 'Novo token';
  static const String ctButtonRefreshList = 'Atualizar lista';
  static const String ctButtonAutoRefreshOn = 'Auto refresh: ligado';
  static const String ctButtonAutoRefreshOff = 'Auto refresh: desligado';
  static const String ctButtonViewDetails = 'Ver detalhes';
  static const String ctButtonCopyTokenId = 'Copiar ID';
  static const String ctTooltipCopyTokenId = 'Copiar ID do token';
  static const String ctInfoTokenIdCopied = 'ID do token copiado';
  static const String ctButtonEdit = 'Editar';
  static const String ctButtonClearFilters = 'Limpar filtros';
  static const String ctSectionRegisteredTokens = 'Tokens cadastrados';
  static const String ctMsgNoTokenFound = 'Nenhum token encontrado.';
  static const String ctMsgNoTokenMatchFilter =
      'Nenhum token corresponde aos filtros aplicados.';
  static const String ctFilterClientId = 'Filtrar por Client ID';
  static const String ctFilterStatus = 'Filtrar por status';
  static const String ctFilterSort = 'Ordenar por';
  static const String ctFilterStatusAll = 'Todos';
  static const String ctFilterStatusActive = 'Ativos';
  static const String ctFilterStatusRevoked = 'Revogados';
  static const String ctSortNewest = 'Mais novos';
  static const String ctSortOldest = 'Mais antigos';
  static const String ctSortClientAsc = 'Client A-Z';
  static const String ctSortClientDesc = 'Client Z-A';
  static const String ctMsgTokenCreatedCopyNow =
      'Token criado com sucesso (copie e guarde agora):';
  static const String ctLabelClient = 'Client';
  static const String ctLabelId = 'ID';
  static const String ctLabelAgent = 'Agent';
  static const String ctLabelCreatedAt = 'Criado em';
  static const String ctLabelStatus = 'Status';
  static const String ctLabelScope = 'Escopo';
  static const String ctLabelRules = 'Regras';
  static const String ctLabelPayload = 'Payload';
  static const String ctScopeAllPermissions = 'Todas as permissões';
  static const String ctScopeRestricted = 'Permissões restritas';
  static const String ctScopeTables = 'Tabelas';
  static const String ctScopeViews = 'Views';
  static const String ctScopeNotInformed = 'não informado pela API';
  static const String ctStatusRevoked = 'revogado';
  static const String ctStatusActive = 'ativo';
  static const String ctButtonRevoked = 'Revogado';
  static const String ctButtonRevoke = 'Revogar';
  static const String ctButtonDelete = 'Excluir';
  static const String ctConfirmRevokeTitle = 'Revogar token';
  static const String ctConfirmRevokeMessage =
      'Tem certeza que deseja revogar este token? O token deixará de funcionar imediatamente.';
  static const String ctConfirmDeleteTitle = 'Excluir token';
  static const String ctConfirmDeleteMessage =
      'Tem certeza que deseja excluir este token? Esta ação não pode ser desfeita.';
  static const String ctErrorClientIdRequired =
      'Informe o client_id para criar o token.';
  static const String ctErrorRuleOrAllPermissionsRequired =
      'Adicione ao menos uma regra valida ou marque all_permissions.';
  static const String ctErrorPayloadMustBeJsonObject =
      'Payload deve ser um objeto JSON valido.';
  static const String ctErrorPayloadInvalidJson = 'Payload JSON invalido.';
  static const String ctRuleFieldType = 'Tipo';
  static const String ctRuleFieldEffect = 'Efeito';
  static const String ctRuleFieldResource = 'Recurso (schema.nome)';
  static const String ctRuleHintResource = 'dbo.clientes';
  static const String ctPermissionRead = 'Read';
  static const String ctPermissionUpdate = 'Update';
  static const String ctPermissionDelete = 'Delete';
  static const String ctGridColumnType = 'Tipo';
  static const String ctGridColumnResource = 'Recurso';
  static const String ctGridColumnEffect = 'Efeito';
  static const String ctGridColumnPermissions = 'Permissões';
  static const String ctGridColumnActions = 'Ações';
  static const String ctNoRulesAdded =
      'Nenhuma regra adicionada. Clique em "Adicionar regra".';
  static const String ctDialogAddRuleTitle = 'Adicionar regra';
  static const String ctDialogCreateTokenTitle = 'Criar token do cliente';
  static const String ctDialogEditTokenTitle = 'Editar token do cliente';
  static const String ctButtonSaveTokenChanges = 'Salvar alterações';
  static const String ctDialogEditRuleTitle = 'Editar regra';
  static const String ctDialogSaveRule = 'Salvar regra';
  static const String ctEditUpdatesTokenHint =
      'As alteracoes serao aplicadas ao token selecionado.';
  static const String ctEditCreatesNewTokenHint =
      'Editar preenche os campos para criar um novo token. '
      'O token original nao e alterado.';
  static const String ctDialogTokenDetailsTitle = 'Detalhes do token';
  static const String ctDialogDeleteRuleTitle = 'Excluir regra';
  static const String ctButtonDeleteRule = 'Excluir regra';
  static const String ctTooltipEditRule = 'Editar regra';
  static const String ctTooltipDeleteRule = 'Excluir regra';
  static const String ctTooltipEditToken = 'Editar token';
  static const String ctErrorRuleResourceRequired =
      'Informe o recurso (schema.nome).';
  static const String ctErrorRulePermissionRequired =
      'Selecione ao menos uma permissão para a regra.';
  static const String ctRuleNoPermission = 'Sem permissões';
  static const String ctToggleKeepConfigAfterCreate =
      'Manter configuração após criar token';
  static const String ctRuleFeedbackAdded = 'Regra adicionada com sucesso.';
  static const String ctRuleFeedbackUpdated = 'Regra atualizada com sucesso.';
  static const String ctRuleFeedbackRemoved = 'Regra removida com sucesso.';

  // Config Navigation Tabs
  static const String configTabGeneral = 'Geral';
  static const String configTabWebSocket = 'WebSocket';
  static const String configLastUpdateNever = 'Nunca verificado';
  static const String configLastUpdateManual = 'Verificação manual';
  static const String configUpdatesNotImplemented =
      'A verificação automática de atualizações será implementada na próxima '
      'etapa.';

  // General Settings
  static const String gsSectionAppearance = 'Aparência';
  static const String gsToggleDarkTheme = 'Tema escuro';
  static const String gsSectionSystem = 'Sistema';
  static const String gsToggleStartWithWindows = 'Iniciar com o Windows';
  static const String gsToggleStartMinimized = 'Iniciar minimizado';
  static const String gsToggleMinimizeToTray = 'Minimizar para bandeja';
  static const String gsToggleCloseToTray = 'Fechar para bandeja';
  static const String gsSectionUpdates = 'Atualizações';
  static const String gsCheckUpdatesWithDate = 'Verificar atualizações';
  static const String gsSectionAbout = 'Sobre';
  static const String gsLabelVersion = 'Versão';
  static const String gsLabelLicense = 'Licença';
  static const String gsLicenseMit = 'MIT License';
  static const String gsButtonOpenSettings = 'Abrir configurações';

  // Database Settings
  static const String dbSectionTitle = 'Configuração do banco de dados';
  static const String dbFieldDatabaseDriver = 'Driver do Banco de Dados';
  static const String dbFieldOdbcDriverName = 'Nome do Driver ODBC';
  static const String dbFieldHost = 'Host';
  static const String dbHintHost = 'localhost';
  static const String dbFieldPort = 'Porta';
  static const String dbHintPort = '1433';
  static const String dbFieldDatabaseName = 'Nome do Banco de Dados';
  static const String dbHintDatabaseName = 'Nome da Base';
  static const String dbFieldUsername = 'Usuário';
  static const String dbHintUsername = 'Usuário';
  static const String dbHintPassword = 'Senha';
  static const String dbButtonTestConnection = 'Testar Conexão com Banco';
  static const String dbTabDatabase = 'Banco de dados';
  static const String dbTabAdvanced = 'Avançado';

  // Main Window
  static const String mainDegradedModeTitle = 'Modo Degradado Ativo';
  static const String mainDegradedModeDescription =
      'O aplicativo está rodando com recursos limitados:';

  // ODBC Advanced Settings
  static const String odbcErrorPoolRange =
      'Tamanho do pool deve ser entre 1 e 20';
  static const String odbcErrorLoginTimeoutRange =
      'Login timeout deve ser entre 1 e 120 segundos';
  static const String odbcErrorBufferRange =
      'Buffer de resultados deve ser entre 8 e 128 MB';
  static const String odbcErrorChunkRange =
      'Chunk do streaming deve ser entre 64 e 8192 KB';
  static const String odbcErrorSaveFailed =
      'Falha ao salvar configurações avançadas. Tente novamente.';
  static const String odbcSuccessAppliedNow =
      'As configurações de pool, timeout e streaming foram salvas e '
      'aplicadas para novas conexões.';
  static const String odbcSuccessAppliedGradually =
      'As configurações de pool, timeout e streaming foram salvas. As novas '
      'opções serão aplicadas gradualmente em novas conexões.';
  static const String odbcModalTitleSaved = 'Configurações salvas';
  static const String odbcSectionTitle = 'Pool de conexões e timeouts';
  static const String odbcBlockPool = 'Pool de Conexões';
  static const String odbcBlockPoolDescription =
      'Múltiplas conexões são reutilizadas automaticamente. Melhora '
      'performance em cenários de alta concorrência.';
  static const String odbcFieldPoolSize = 'Tamanho máximo do pool';
  static const String odbcHintPoolSize = '4';
  static const String odbcBlockTimeouts = 'Timeouts';
  static const String odbcFieldLoginTimeout = 'Login timeout (segundos)';
  static const String odbcHintLoginTimeout = '30';
  static const String odbcFieldResultBuffer = 'Buffer de resultados (MB)';
  static const String odbcHintResultBuffer = '32';
  static const String odbcTextResultBufferHelp =
      'Tamanho máximo do buffer em memória para resultados de queries. '
      'Aumentar pode melhorar performance em queries grandes.';
  static const String odbcBlockStreaming = 'Streaming';
  static const String odbcFieldChunkSize = 'Tamanho do chunk (KB)';
  static const String odbcHintChunkSize = '1024';
  static const String odbcTextStreamingHelp =
      'Controla o tamanho dos chunks enviados para a UI durante queries em '
      'streaming. Valores maiores reduzem eventos de atualização e podem '
      'melhorar throughput.';
  static const String odbcTextQuickRecommendation = 'Recomendação rápida:';
  static const String odbcTextQuickRecommendationItems =
      '• 256-512 KB: feedback visual mais frequente\n'
      '• 1024 KB: equilíbrio geral (padrão)\n'
      '• 2048-4096 KB: maior throughput em datasets grandes';
  static const String odbcTextChunkWarning =
      'Se houver travamentos de UI ou uso alto de memória, reduza o chunk.';
  static const String odbcButtonRestoreDefault = 'Restaurar padrão';
  static const String odbcButtonSaveAdvanced = 'Salvar configurações avançadas';

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

  /// Returns contextual delete-rule confirmation message.
  static String ctDeleteRuleConfirmation({
    required String resourceType,
    required String resourceName,
  }) {
    return 'Deseja realmente excluir a regra "$resourceType: $resourceName"?';
  }

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
  static const String querySqlLabel = 'Consulta SQL';
  static const String querySqlHint = 'SELECT * FROM tabela...';
  static const String queryActionExecute = 'Executar';
  static const String queryActionTestConnection = 'Testar Conexão';
  static const String queryActionClear = 'Limpar';
  static const String queryActionCancel = 'Cancelar';
  static const String queryConnectionStatusTitle = 'Status da Conexão';
  static const String queryConnectionTesting = 'Testando conexão...';
  static const String queryConnectionSuccess =
      'Conexão estabelecida com sucesso';
  static const String queryConnectionFailure = 'Falha na conexão';
  static const String queryCancelledByUser = 'Query cancelada pelo usuário';
  static const String queryStreamingErrorPrefix = 'Erro no streaming';
  static const String queryStreamingMode = 'Modo streaming';
  static const String queryStreamingModeHint =
      'Para grandes datasets (milhares de linhas)';
  static const String queryStreamingProgress = 'Processando';
  static const String queryStreamingRows = 'linhas';
  static const String queryPaginationPage = 'Pagina';
  static const String queryPaginationPageSize = 'Linhas por pagina';
  static const String queryPaginationPrevious = 'Anterior';
  static const String queryPaginationNext = 'Proxima';
  static const String queryPaginationShowing = 'Exibindo';
  static const String queryResultSetLabel = 'Result set';

  // Dashboard
  static const String dashboardDescription =
      'Monitor your agent status and database connections here.';
  static const String dashboardMetricsTitle = 'Métricas ODBC';
  static const String dashboardMetricsQueries = 'Queries executadas';
  static const String dashboardMetricsSuccess = 'Sucesso';
  static const String dashboardMetricsErrors = 'Erros';
  static const String dashboardMetricsSuccessRate = 'Taxa de sucesso';
  static const String dashboardMetricsAvgLatency = 'Latência média';
  static const String dashboardMetricsMaxLatency = 'Latência máxima';
  static const String dashboardMetricsTotalRows = 'Total de linhas';
  static const String dashboardMetricsPeriod = 'Período';
  static const String dashboardMetricsPeriod1h = 'Última 1h';
  static const String dashboardMetricsPeriod24h = 'Últimas 24h';
  static const String dashboardMetricsPeriodAll = 'Total';

  // WebSocket Log Viewer
  static const String wsLogTitle = 'WebSocket Messages';
  static const String wsLogEnabled = 'Enabled';
  static const String wsLogClear = 'Clear';
  static const String wsLogNoMessages = 'No messages yet';
  static const String wsLogAuthChecks = 'Auth checks';
  static const String wsLogAllowed = 'Allowed';
  static const String wsLogDenied = 'Denied';
  static const String wsLogDenialRate = 'Denial rate';
}

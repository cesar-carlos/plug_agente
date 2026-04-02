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
  static const String tabClientTokenAuthorization = 'Autorização de Token do Cliente';
  static const String tabWebSocketDiagnostics = 'Diagnóstico';
  static const String navSettings = 'Configurações';
  static const String navDatabaseSettings = 'Banco de dados';
  static const String navAgentProfile = 'Perfil do agente';

  // Agent Profile
  static const String agentProfilePageTitle = 'Perfil do agente';
  static const String agentProfileLoading = 'Carregando perfil do agente...';
  static const String agentProfileFormSectionTitle = 'Dados cadastrais';
  static const String agentProfileSectionIdentity = 'Identificação';
  static const String agentProfileSectionContact = 'Contato';
  static const String agentProfileSectionAddress = 'Endereço';
  static const String agentProfileSectionNotes = 'Observações';
  static const String agentProfileFieldName = 'Nome';
  static const String agentProfileFieldTradeName = 'Nome fantasia';
  static const String agentProfileFieldDocument = 'CPF/CNPJ';
  static const String agentProfileFieldPhone = 'Telefone';
  static const String agentProfileFieldMobile = 'Celular';
  static const String agentProfileFieldEmail = 'E-mail';
  static const String agentProfileFieldStreet = 'Endereço';
  static const String agentProfileFieldNumber = 'Número';
  static const String agentProfileFieldDistrict = 'Bairro';
  static const String agentProfileFieldPostalCode = 'CEP';
  static const String agentProfileFieldCity = 'Município';
  static const String agentProfileFieldState = 'UF';
  static const String agentProfileFieldNotes = 'Observação';
  static const String agentProfileActionLookupCnpj = 'Consultar CNPJ';
  static const String agentProfileActionLookupCep = 'Consultar CEP';
  static const String agentProfileActionSave = 'Salvar perfil';
  static const String agentProfileLookupCnpjInvalid = 'Informe um CNPJ válido com 14 dígitos para consulta.';
  static const String agentProfileLookupCepInvalid = 'Informe um CEP válido com 8 dígitos para consulta.';
  static const String agentProfileSaveSuccess = 'Perfil do agente salvo com sucesso.';

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
  static const String modalTitleErrorTestingConnection = 'Erro ao Testar Conexão';
  static const String modalTitleErrorVerifyingDriver = 'Erro ao Verificar Driver';
  static const String modalTitleErrorSaving = 'Erro ao Salvar';
  static const String modalTitleConnectionStatus = 'Status da Conexão';

  // Success Messages
  static const String msgAuthenticatedSuccessfully = 'Autenticado com sucesso!';
  static const String msgWebSocketConnectedSuccessfully = 'Conectado ao servidor WebSocket com sucesso!';
  static const String msgDatabaseConnectionSuccessful = 'Conexão com o banco de dados estabelecida com sucesso!';
  static const String msgConfigSavedSuccessfully = 'Configuração salva com sucesso!';
  static const String msgConnectionSuccessful = 'sucesso';

  // Error Messages
  static const String msgOdbcDriverNameRequired = 'Nome do Driver ODBC é obrigatório';
  static const String msgServerUrlRequired = 'URL do Servidor é obrigatória';
  static const String msgAgentIdRequired = 'ID do Agente é obrigatório';
  static const String msgAuthCredentialsRequired = 'Usuário e senha são obrigatórios';

  // Shared form controls (AppTextField, AppDropdown, AppFieldSpecs)
  static const String formDropdownSelectPrefix = 'Selecione ';
  static const String formFieldLabelPassword = 'Senha';
  static const String formPasswordDefaultHint = 'Digite a senha';
  static const String formNumericInvalidValue = 'Valor inválido';
  static const String formHintCep = '00.000-000';
  static const String formHintPhone = '(00) 0000-0000';
  static const String formHintMobile = '(00) 00000-0000';
  static const String formHintDocument = '000.000.000-00 ou 00.000.000/0000-00';
  static const String formHintState = 'SP';
  static const String formValidationEmailInvalid = 'E-mail inválido';
  static const String formValidationUrlHttpHttps = 'Informe uma URL com http:// ou https://';
  static const String formValidationCepDigits = 'CEP deve ter 8 dígitos';
  static const String formValidationPhoneDigits = 'Telefone deve ter 10 dígitos (DDD + número)';
  static const String formValidationMobileDigits = 'Celular deve ter 11 dígitos';
  static const String formValidationMobileNineAfterDdd = 'Celular deve começar com 9 após o DDD';
  static const String formValidationDocumentDigits = 'CPF (11) ou CNPJ (14) dígitos';
  static const String formValidationStateLetters = 'UF com 2 letras';

  static String formFieldRequired(String fieldLabel) => '$fieldLabel é obrigatório';

  static String formPasswordRequired(String fieldLabel) => '$fieldLabel é obrigatória';

  static String formNumericMinValue(int min) => 'Valor mínimo: $min';

  static String formNumericMaxValue(int max) => 'Valor máximo: $max';

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

  static const String wsSectionOutboundCompression = 'Compressão de envio (agente → hub)';
  static const String wsFieldOutboundCompressionMode = 'Modo';
  static const String wsOutboundCompressionOff = 'Desligado';
  static const String wsOutboundCompressionGzip = 'Sempre GZIP';
  static const String wsOutboundCompressionAuto = 'Automático';
  static const String wsOutboundCompressionDescription =
      'Automático: acima do limite negociado, o agente comprime com GZIP apenas '
      'se o resultado for menor que o JSON em UTF-8 (evita CPU e tráfego em '
      'dados pouco compressíveis).';

  // Diagnostics (advanced)
  static const String diagnosticsSectionTitle = 'Diagnóstico avançado';
  static const String diagnosticsWarningTitle = 'Dados sensíveis nos logs';
  static const String diagnosticsWarningBody =
      'As opções abaixo podem gravar SQL ou detalhes técnicos nos logs do '
      'aplicativo. Use apenas para depuração e desative em produção quando '
      'houver dados pessoais ou segredos.';
  static const String diagnosticsOdbcPaginatedSqlLogLabel = 'Log de SQL paginada (ODBC)';
  static const String diagnosticsOdbcPaginatedSqlLogDescription =
      'Quando ativado, o agente registra a SQL final após reescrita de '
      'paginação gerenciada (developer log).';

  // Client Token Settings
  static const String ctSectionTitle = 'Client Token Authorization';
  static const String ctFieldClientId = 'Client ID (gerado automaticamente)';
  static const String ctFieldAgentIdOptional = 'Agent ID (opcional)';
  static const String ctFieldPayloadJsonOptional = 'Payload JSON (opcional)';
  static const String ctHintClientId = 'Gerado automaticamente';
  static const String ctHintAgentId = 'agent-01';
  static const String ctHintPayloadJson = '{"display_name":"Acme ERP","env":"production"}';
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
  static const String ctButtonCopyClientToken = 'Copiar token';
  static const String ctTooltipCopyClientToken = 'Copiar token do cliente';
  static const String ctInfoClientTokenCopied = 'Token do cliente copiado';
  static const String ctInfoClientTokenUnavailable =
      'Token indisponivel para este registro. Gere um novo token para copiar o valor secreto.';
  static const String ctButtonEdit = 'Editar';
  static const String ctButtonClearFilters = 'Limpar filtros';
  static const String ctSectionRegisteredTokens = 'Tokens cadastrados';
  static const String ctMsgNoTokenFound = 'Nenhum token encontrado.';
  static const String ctMsgNoTokenMatchFilter = 'Nenhum token corresponde aos filtros aplicados.';
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
  static const String ctMsgTokenCreatedCopyNow = 'Token criado com sucesso (copie e guarde agora):';
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
  static const String ctErrorClientIdRequired = 'Informe o client_id para criar o token.';
  static const String ctErrorRuleOrAllPermissionsRequired =
      'Adicione ao menos uma regra valida ou marque all_permissions.';
  static const String ctErrorPayloadMustBeJsonObject = 'Payload deve ser um objeto JSON valido.';
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
  static const String ctNoRulesAdded = 'Nenhuma regra adicionada. Clique em "Adicionar regra".';
  static const String ctDialogAddRuleTitle = 'Adicionar regra';
  static const String ctDialogCreateTokenTitle = 'Criar token do cliente';
  static const String ctDialogEditTokenTitle = 'Editar token do cliente';
  static const String ctButtonSaveTokenChanges = 'Salvar alterações';
  static const String ctDialogEditRuleTitle = 'Editar regra';
  static const String ctDialogSaveRule = 'Salvar regra';
  static const String ctEditUpdatesTokenHint = 'As alteracoes serao aplicadas ao token selecionado.';
  static const String ctEditCreatesNewTokenHint =
      'Editar preenche os campos para criar um novo token. '
      'O token original nao e alterado.';
  static const String ctDialogTokenDetailsTitle = 'Detalhes do token';
  static const String ctDialogDeleteRuleTitle = 'Excluir regra';
  static const String ctButtonDeleteRule = 'Excluir regra';
  static const String ctTooltipEditRule = 'Editar regra';
  static const String ctTooltipDeleteRule = 'Excluir regra';
  static const String ctTooltipEditToken = 'Editar token';
  static const String ctErrorRuleResourceRequired = 'Informe o recurso (schema.nome).';
  static const String ctErrorRulePermissionRequired = 'Selecione ao menos uma permissão para a regra.';
  static const String ctRuleNoPermission = 'Sem permissões';
  static const String ctToggleKeepConfigAfterCreate = 'Manter configuração após criar token';
  static const String ctRuleFeedbackAdded = 'Regra adicionada com sucesso.';
  static const String ctRuleFeedbackUpdated = 'Regra atualizada com sucesso.';
  static const String ctRuleFeedbackRemoved = 'Regra removida com sucesso.';

  // Config Navigation Tabs
  static const String configTabGeneral = 'Geral';
  static const String configTabWebSocket = 'WebSocket';
  static const String configLastUpdateNever = 'Nunca verificado';
  static const String configLastUpdateManual = 'Verificação manual';
  static const String configUpdatesChecking = 'Verificando atualizações...';
  static const String configUpdatesAvailable = 'Uma nova versão está disponível. Siga as instruções para atualizar.';
  static const String configUpdatesNotAvailable = 'Você já está na versão mais recente.';
  static const String configUpdatesTriggered = 'Verificação de atualizações iniciada.';
  static const String configLastUpdatePrefix = 'Última verificação: ';

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
  static const String gsAutoUpdateNotConfigured =
      'Auto-update nao esta configurado. Defina AUTO_UPDATE_FEED_URL com um feed Sparkle (.xml).';
  static const String gsAutoUpdateNotSupported = 'Auto-update nao suportado neste modo de execucao.';
  static const String gsSectionAbout = 'Sobre';
  static const String gsLabelVersion = 'Versão';
  static const String gsLabelLicense = 'Licença';
  static const String gsLicenseMit = 'MIT License';
  static const String gsButtonOpenSettings = 'Abrir configurações';

  // Single Instance (used by native runner; kept here for consistency)
  // Must match constants/autostart_arg.txt and installer/constants.iss
  static const String singleInstanceArgAutostart = '--autostart';
  static const String singleInstanceTitle = 'Plug Agente';
  static const String singleInstanceMessage = 'O aplicativo Plug Agente já está em execução.';
  static const String singleInstanceMessageWithUser = 'O aplicativo Plug Agente já está em execução.\n\nUsuário: ';

  // Bootstrap Failure (startup error screen)
  static const String bootstrapFailureTitle = 'Falha na inicializacao';
  static const String bootstrapFailureButtonClose = 'Fechar aplicativo';
  static const String bootstrapFailureTechnicalDetails = 'Detalhes tecnicos:';
  static const String bootstrapFailureStorageMessage =
      'Nao foi possivel iniciar porque o aplicativo nao conseguiu '
      'acessar um diretorio global de configuracao.\n\n'
      'Execute o Plug Agente como administrador ou ajuste as permissoes '
      'de escrita em ProgramData/Public Documents.';
  static const String bootstrapFailureGenericMessage =
      'Ocorreu uma falha durante a inicializacao do aplicativo. '
      'Feche e abra novamente. Se o problema persistir, execute como '
      'administrador e revise as permissoes do sistema.';

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
  static const String mainDegradedModeDescription = 'O aplicativo está rodando com recursos limitados:';

  // ODBC Advanced Settings
  static const String odbcErrorPoolRange = 'Tamanho do pool deve ser entre 1 e 20';
  static const String odbcErrorLoginTimeoutRange = 'Login timeout deve ser entre 1 e 120 segundos';
  static const String odbcErrorBufferRange = 'Buffer de resultados deve ser entre 8 e 128 MB';
  static const String odbcErrorChunkRange = 'Chunk do streaming deve ser entre 64 e 8192 KB';
  static const String odbcErrorSaveFailed = 'Falha ao salvar configurações avançadas. Tente novamente.';
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
  static const String odbcFieldNativePool = 'Pool nativo ODBC (experimental)';
  static const String odbcTextNativePoolHelp =
      'Desligado por padrão: cada consulta usa conexão dedicada com buffer '
      'configurado (mais estável). Ative apenas para testar desempenho ou '
      'quando o driver/pacote tratar buffers no pool nativo. '
      'Após alterar, reinicie o aplicativo para o modo valer de fato.';
  static const String odbcSuccessPoolModeRestartAppend =
      ' Reinicie o aplicativo para aplicar a troca do modo de pool ODBC.';
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
  static const String odbcTextChunkWarning = 'Se houver travamentos de UI ou uso alto de memória, reduza o chunk.';
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
  static const String btnRetry = 'Tentar Novamente';

  // Error Display Titles (Failure codes)
  static const String errorTitleValidation = 'Dados Inválidos';
  static const String errorTitleNetwork = 'Erro de Rede';
  static const String errorTitleDatabase = 'Erro no Banco de Dados';
  static const String errorTitleServer = 'Erro no Servidor';
  static const String errorTitleNotFound = 'Não Encontrado';

  // Query Results
  static const String queryNoResults = 'Sem resultados';
  static const String queryNoResultsMessage = 'Execute uma consulta SELECT para ver os resultados aqui.';
  static const String queryErrorTitle = 'Erro na Consulta';
  static const String queryValidationEmpty = 'A query não pode estar vazia';
  static const String queryValidationConnectionStringEmpty = 'A string de conexão não pode estar vazia';
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
  static const String queryConnectionSuccess = 'Conexão estabelecida com sucesso';
  static const String queryConnectionFailure = 'Falha na conexão';
  static const String queryCancelledByUser = 'Query cancelada pelo usuário';
  static const String connectionStatusConnected = 'Conectado';
  static const String connectionStatusConnecting = 'Conectando...';
  static const String connectionStatusError = 'Erro de conexão';
  static const String connectionStatusDisconnected = 'Desconectado';
  static const String connectionStatusHubConnected = 'Hub: Conectado';
  static const String connectionStatusHubConnecting = 'Hub: Conectando...';
  static const String connectionStatusHubReconnecting = 'Hub: Reconectando...';
  static const String connectionStatusHubError = 'Hub: Erro de conexão';
  static const String connectionStatusHubDisconnected = 'Hub: Desconectado';
  static const String connectionStatusDatabaseConnected = 'BD: Conectado';
  static const String connectionStatusDatabaseDisconnected = 'BD: Desconectado';
  static const String connectionStatusDatabaseTooltip =
      'Última verificação ODBC bem-sucedida (teste de conexão ou consulta). '
      'Não indica uma sessão permanente com o banco.';
  static const String queryStreamingErrorPrefix = 'Erro no streaming';
  static const String queryStreamingMode = 'Modo streaming';
  static const String querySqlHandlingModePreserve = 'Preservar SQL';
  static const String playgroundDescription =
      'Escreva consultas SQL, teste a conexão e acompanhe os resultados em tempo real.';
  static const String playgroundShortcutExecute = 'F5 ou Ctrl+Enter para executar';
  static const String playgroundShortcutTestConnection = 'Ctrl+Shift+C para testar a conexão';
  static const String playgroundShortcutClear = 'Ctrl+L para limpar o editor';
  static const String querySqlHandlingModePreserveHint =
      'Executa a SQL exatamente como enviada, sem reescrita de paginação';
  static const String queryPlaygroundHintLastRunPreserve =
      'Última execução: SQL preservada (sem reescrita de paginação pelo agente).';
  static const String queryPlaygroundHintLastRunManagedPagination =
      'Última execução: paginação gerenciada — a SQL pode ter sido reescrita para o dialeto do banco.';
  static const String queryPlaygroundHintLastRunManaged =
      'Última execução: modo gerenciado — limites e ajustes do agente podem aplicar-se à SQL.';
  static const String queryPlaygroundHintLastRunStreaming =
      'Última execução: modo streaming — resultados recebidos em fluxo contínuo.';
  static const String queryPlaygroundStreamingRowCapHint =
      'Exibição limitada a {max} linhas no streaming (memória). A consulta no '
      'servidor foi interrompida ao atingir esse limite.';
  static const String wsLogPreserveSqlDeprecatedUses = 'Uso de preserve_sql (deprecated)';
  static const String queryStreamingModeHint = 'Para grandes datasets (milhares de linhas)';
  static const String queryStreamingProgress = 'Processando';
  static const String queryStreamingRows = 'linhas';
  static const String queryPaginationPage = 'Pagina';
  static const String queryPaginationPageSize = 'Linhas por pagina';
  static const String queryPaginationPrevious = 'Anterior';
  static const String queryPaginationNext = 'Proxima';
  static const String queryPaginationShowing = 'Exibindo';
  static const String queryResultSetLabel = 'Result set';

  // External lookups (OpenCNPJ / ViaCEP)
  static const String msgOpenCnpjEmptyResponse = 'Resposta vazia do serviço de consulta de CNPJ.';
  static const String msgOpenCnpjInvalidPayload = 'Resposta inválida do serviço de consulta de CNPJ.';
  static const String msgOpenCnpjNotFound = 'CNPJ não encontrado na base consultada.';
  static const String msgOpenCnpjRateLimit =
      'Limite de consultas ao serviço de CNPJ excedido. Tente novamente em instantes.';
  static const String msgOpenCnpjNetworkError = 'Não foi possível consultar o CNPJ. Verifique a conexão.';
  static const String msgOpenCnpjUnexpectedError = 'Erro inesperado ao consultar o CNPJ.';
  static const String msgViaCepNotFound = 'CEP não encontrado.';
  static const String msgViaCepEmptyResponse = 'Resposta vazia do serviço de consulta de CEP.';
  static const String msgViaCepInvalidPayload = 'Resposta inválida do serviço de consulta de CEP.';
  static const String msgViaCepNetworkError = 'Não foi possível consultar o CEP. Verifique a conexão.';
  static const String msgViaCepUnexpectedError = 'Erro inesperado ao consultar o CEP.';

  // Dashboard
  static const String dashboardDescription = 'Monitore o status do agente e das conexões com o banco em um só lugar.';
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
  static const String wsLogP95Latency = 'P95 auth latency';
  static const String wsLogP99Latency = 'P99 auth latency';
}

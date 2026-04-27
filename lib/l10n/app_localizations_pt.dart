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
  String get navPlayground => 'Playground';

  @override
  String get navSettings => 'Configurações';

  @override
  String get navAgentProfile => 'Perfil do agente';

  @override
  String get navDatabaseSettings => 'Banco de dados';

  @override
  String get navWebSocketSettings => 'Conexão WebSocket';

  @override
  String formFieldRequired(String fieldLabel) {
    return '$fieldLabel é obrigatório.';
  }

  @override
  String get agentProfileLoading => 'Carregando perfil do agente...';

  @override
  String get agentProfileFormSectionTitle => 'Dados cadastrais';

  @override
  String get agentProfileSectionIdentity => 'Identificação';

  @override
  String get agentProfileSectionContact => 'Contato';

  @override
  String get agentProfileSectionAddress => 'Endereço';

  @override
  String get agentProfileSectionNotes => 'Observações';

  @override
  String get agentProfileFieldName => 'Nome';

  @override
  String get agentProfileFieldTradeName => 'Nome fantasia';

  @override
  String get agentProfileFieldDocument => 'CPF/CNPJ';

  @override
  String get agentProfileFieldPhone => 'Telefone';

  @override
  String get agentProfileFieldMobile => 'Celular';

  @override
  String get agentProfileFieldEmail => 'E-mail';

  @override
  String get agentProfileFieldStreet => 'Endereço';

  @override
  String get agentProfileFieldNumber => 'Número';

  @override
  String get agentProfileFieldDistrict => 'Bairro';

  @override
  String get agentProfileFieldPostalCode => 'CEP';

  @override
  String get agentProfileFieldCity => 'Município';

  @override
  String get agentProfileFieldState => 'UF';

  @override
  String get agentProfileFieldNotes => 'Observação';

  @override
  String get agentProfileActionLookupCnpj => 'Consultar CNPJ';

  @override
  String get agentProfileActionLookupCep => 'Consultar CEP';

  @override
  String get agentProfileActionSave => 'Salvar perfil';

  @override
  String get agentProfileLookupCnpjInvalid => 'Informe um CNPJ válido com 14 dígitos para consulta.';

  @override
  String get agentProfileLookupCepInvalid => 'Informe um CEP válido com 8 dígitos para consulta.';

  @override
  String agentProfileValidationMaxLength(String fieldLabel, int maxLength) {
    return '$fieldLabel deve ter no máximo $maxLength caracteres.';
  }

  @override
  String agentProfileValidationNotesMaxLength(int max) {
    return 'A observação deve ter no máximo $max caracteres.';
  }

  @override
  String get agentProfileValidationDocumentInvalid => 'CPF/CNPJ inválido.';

  @override
  String get agentProfileValidationPostalCodeInvalid => 'CEP inválido. Informe 8 dígitos.';

  @override
  String get agentProfileValidationPhoneInvalid => 'Telefone inválido.';

  @override
  String get agentProfileValidationMobileInvalid => 'Celular inválido.';

  @override
  String get agentProfileValidationEmailInvalid => 'E-mail inválido.';

  @override
  String get agentProfileValidationDocumentTypeMismatch => 'O tipo de documento não corresponde ao CPF/CNPJ informado.';

  @override
  String get agentProfileValidationDocumentTypeEnum => 'O tipo de documento deve ser cpf ou cnpj.';

  @override
  String get agentProfileValidationStateInvalid => 'A UF deve ter exatamente 2 letras.';

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
  String get msgWebSocketConnectedSuccessfully => 'Conectado ao servidor WebSocket com sucesso!';

  @override
  String get msgDatabaseConnectionSuccessful => 'Conexão com o banco de dados estabelecida com sucesso!';

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
  String get queryNoResults => 'Sem resultados';

  @override
  String get queryNoResultsMessage => 'Execute uma consulta SELECT para ver os resultados aqui.';

  @override
  String get queryTotalRecords => 'Total de registros';

  @override
  String get queryExecutionTime => 'Tempo de execução';

  @override
  String get queryAffectedRows => 'Linhas afetadas';

  @override
  String get dashboardDescription => 'Monitore o status do seu agente e conexões de banco de dados aqui.';

  @override
  String get odbcDriverNotFound =>
      'O driver ODBC configurado não foi encontrado neste computador. Revise o driver e a fonte de dados nas configurações.';

  @override
  String get odbcAuthFailed => 'Não foi possível autenticar no banco de dados. Verifique usuário, senha e permissões.';

  @override
  String get odbcServerUnreachable =>
      'Não foi possível conectar ao servidor do banco. Verifique host, porta, VPN e disponibilidade da rede.';

  @override
  String get odbcConnectionTimeout =>
      'A conexão com o banco demorou mais do que o esperado. Confirme se o servidor está acessível e tente novamente.';

  @override
  String get odbcConnectionFailed => 'Não foi possível estabelecer conexão com o banco de dados.';

  @override
  String get odbcDetailPrefix => 'Detalhe ODBC';

  @override
  String get agentProfileSaveSuccessLocal => 'Perfil guardado neste computador.';

  @override
  String get agentProfileSaveSuccessSynced => 'Perfil guardado e sincronizado com o servidor.';

  @override
  String get agentProfileHubSavePartialTitle => 'Guardado localmente';

  @override
  String agentProfileHubSavePartialMessage(String errorDetail) {
    return 'O perfil foi guardado neste computador, mas a atualização no servidor falhou. Os dados serão enviados na próxima ligação.\n\nDetalhe: $errorDetail';
  }

  @override
  String get dashboardMetricsTitle => 'Métricas ODBC';

  @override
  String get dashboardMetricsQueries => 'Consultas executadas';

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
  String get wsLogEnabled => 'Ativado';

  @override
  String get wsLogClear => 'Limpar';

  @override
  String get wsLogNoMessages => 'Nenhuma mensagem ainda';

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
  String get wsLogPreserveSqlDeprecatedUses => 'Uso de preserve_sql (deprecated)';

  @override
  String get mainDegradedModeTitle => 'Modo degradado ativo';

  @override
  String get mainDegradedModeDescription => 'O aplicativo está rodando com recursos limitados:';

  @override
  String get playgroundDescription => 'Escreva consultas SQL, teste a conexão e acompanhe os resultados em tempo real.';

  @override
  String get playgroundShortcutExecute => 'F5 ou Ctrl+Enter para executar';

  @override
  String get playgroundShortcutTestConnection => 'Ctrl+Shift+C para testar a conexão';

  @override
  String get playgroundShortcutClear => 'Ctrl+L para limpar o editor';

  @override
  String get queryErrorTitle => 'Erro na consulta';

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
  String get formDropdownSelectPrefix => 'Selecione ';

  @override
  String get queryConnectionStatusTitle => 'Status da conexão';

  @override
  String get queryValidationEmpty => 'A query não pode estar vazia';

  @override
  String get queryValidationConnectionStringEmpty => 'A string de conexão não pode estar vazia';

  @override
  String get queryConnectionTesting => 'Testando conexão...';

  @override
  String get queryConnectionSuccess => 'Conexão estabelecida com sucesso';

  @override
  String get queryConnectionFailure => 'Falha na conexão';

  @override
  String get queryCancelledByUser => 'Query cancelada pelo usuário';

  @override
  String get queryStreamingErrorPrefix => 'Erro no streaming';

  @override
  String queryPlaygroundStreamingRowCapHint(int max) {
    return 'Exibição limitada a $max linhas no streaming (memória). A consulta no servidor foi interrompida ao atingir esse limite.';
  }

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
  String get querySqlHandlingModePreserve => 'Preservar SQL';

  @override
  String get querySqlHandlingModePreserveHint =>
      'Executa a SQL exatamente como enviada, sem reescrita de paginação gerenciada';

  @override
  String get queryStreamingMode => 'Modo streaming';

  @override
  String get queryStreamingModeHint => 'Para grandes conjuntos de dados (milhares de linhas)';

  @override
  String get queryErrorShowDetails => 'Ver detalhes';

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
  String get queryResultSetLabel => 'Result set';

  @override
  String get btnRetry => 'Tentar novamente';

  @override
  String get queryExecuteUnexpectedError => 'Erro ao executar a consulta';

  @override
  String odbcDriverNotFoundTest(String driverName) {
    return 'Driver ODBC \"$driverName\" não foi encontrado. Verifique se o driver está instalado antes de testar a conexão.';
  }

  @override
  String odbcDriverNotFoundSave(String driverName) {
    return 'Driver ODBC \"$driverName\" não foi encontrado. Verifique se o driver está instalado antes de salvar a configuração.';
  }

  @override
  String get configTabGeneral => 'Geral';

  @override
  String get configTabWebSocket => 'WebSocket';

  @override
  String get configLastUpdateNever => 'Nunca verificado';

  @override
  String get configUpdatesChecking => 'Verificando atualizações...';

  @override
  String get configLastUpdatePrefix => 'Última verificação: ';

  @override
  String get configUpdatesAvailable => 'Uma nova versão está disponível. Siga as instruções para atualizar.';

  @override
  String get configUpdatesNotAvailable => 'Você já está na versão mais recente.';

  @override
  String get configUpdatesNotAvailableHint =>
      'Se você acabou de publicar uma nova versão, aguarde até 5 minutos e tente novamente.';

  @override
  String get configAutoUpdateNotConfigured =>
      'Auto-update não está configurado. Defina AUTO_UPDATE_FEED_URL com um feed Sparkle (.xml).';

  @override
  String configAutoUpdateOfficialFeedExpected(String url) {
    return 'Feed oficial esperado: $url';
  }

  @override
  String get configAutoUpdateNotSupported => 'Auto-update não suportado neste modo de execução.';

  @override
  String get configUpdateTechnicalNoData => 'Sem dados técnicos para a verificação atual.';

  @override
  String get configUpdateTechnicalTitle => 'Detalhes técnicos';

  @override
  String get configUpdateTechnicalCurrentVersion => 'Versão atual';

  @override
  String get configUpdateTechnicalCheckedAt => 'Checado em';

  @override
  String get configUpdateTechnicalConfiguredFeed => 'Feed configurado';

  @override
  String get configUpdateTechnicalRequestedFeed => 'Feed consultado';

  @override
  String get configUpdateTechnicalOfficialFeedYes => 'sim';

  @override
  String get configUpdateTechnicalOfficialFeedNo => 'não';

  @override
  String get configUpdateTechnicalOfficialFeed => 'Feed oficial';

  @override
  String get configUpdateTechnicalFeedItemCount => 'Itens no feed';

  @override
  String get configUpdateTechnicalRemoteVersion => 'Versão remota';

  @override
  String get configUpdateTechnicalUpdaterError => 'Erro do updater';

  @override
  String get configUpdateTechnicalAppcastError => 'Erro ao ler appcast';

  @override
  String get gsSectionAppearance => 'Aparência';

  @override
  String get gsToggleDarkTheme => 'Tema escuro';

  @override
  String get gsSectionSystem => 'Sistema';

  @override
  String get gsToggleStartWithWindows => 'Iniciar com o Windows';

  @override
  String get gsToggleStartMinimized => 'Iniciar minimizado';

  @override
  String get gsToggleMinimizeToTray => 'Minimizar para bandeja';

  @override
  String get gsToggleCloseToTray => 'Fechar para bandeja';

  @override
  String get gsSectionUpdates => 'Atualizações';

  @override
  String get gsCheckUpdatesWithDate => 'Verificar atualizações';

  @override
  String get gsSectionAbout => 'Sobre';

  @override
  String get gsLabelVersion => 'Versão';

  @override
  String get gsLabelLicense => 'Licença';

  @override
  String get gsLicenseMit => 'MIT License';

  @override
  String get gsButtonOpenSettings => 'Abrir configurações';

  @override
  String get gsErrorStartupToggleFailed => 'Falha ao alterar configuração de inicialização';

  @override
  String get gsErrorStartupServiceUnavailable => 'Configurações de inicialização não disponíveis neste ambiente';

  @override
  String get gsErrorStartupOpenSystemSettingsFailed => 'Falha ao abrir configurações do sistema';

  @override
  String gsErrorWithDetail(String message, String detail) {
    return '$message: $detail';
  }

  @override
  String get gsStartupEnabledSuccess => 'Inicialização com o Windows ativada';

  @override
  String get gsStartupDisabledSuccess => 'Inicialização com o Windows desativada';

  @override
  String get diagnosticsSectionTitle => 'Diagnóstico avançado';

  @override
  String get diagnosticsWarningTitle => 'Dados sensíveis nos logs';

  @override
  String get diagnosticsWarningBody =>
      'As opções abaixo podem gravar SQL ou detalhes técnicos nos logs do aplicativo. Use apenas para depuração e desative em produção quando houver dados pessoais ou segredos.';

  @override
  String get diagnosticsOdbcPaginatedSqlLogLabel => 'Log de SQL paginada (ODBC)';

  @override
  String get diagnosticsOdbcPaginatedSqlLogDescription =>
      'Quando ativado, o agente registra a SQL final após reescrita de paginação gerenciada (developer log).';

  @override
  String get diagnosticsHubReconnectSectionTitle => 'Reconexão com o hub (recuperação offline)';

  @override
  String get diagnosticsHubReconnectMaxTicksLabel => 'Máximo de tentativas falhas antes de desistir';

  @override
  String get diagnosticsHubReconnectMaxTicksHint =>
      '0 mantém tentativas indefinidamente. Valores menores param antes com erro.';

  @override
  String get diagnosticsHubReconnectIntervalLabel => 'Segundos entre tentativas (após o burst)';

  @override
  String get diagnosticsHubReconnectIntervalHint =>
      'Intervalo permitido: 5–86400. Mudanças no intervalo valem na próxima vez que a retentativa persistente iniciar.';

  @override
  String get diagnosticsHubReconnectEnvHint =>
      'Se você limpar as preferências (Usar padrões), os valores ainda podem vir de HUB_PERSISTENT_RETRY_MAX_FAILED_TICKS e HUB_PERSISTENT_RETRY_INTERVAL_SECONDS no arquivo de ambiente e, em seguida, dos padrões internos.';

  @override
  String get diagnosticsHubReconnectApply => 'Aplicar ajustes de reconexão';

  @override
  String get diagnosticsHubReconnectReset => 'Usar padrões';

  @override
  String get diagnosticsHubReconnectSavedMessage => 'Ajustes de reconexão com o hub foram salvos.';

  @override
  String get diagnosticsHubReconnectInvalidMaxTicks => 'Digite um número inteiro não negativo.';

  @override
  String get diagnosticsHubReconnectInvalidInterval => 'Digite um número inteiro entre 5 e 86400.';

  @override
  String get msgServerUrlRequired => 'URL do servidor é obrigatória';

  @override
  String get msgAgentIdRequired => 'ID do agente é obrigatório';

  @override
  String get msgAuthCredentialsRequired => 'Usuário e senha são obrigatórios';

  @override
  String get msgLoginRequiredBeforeConnect => 'Faça login antes de conectar ao hub';

  @override
  String get msgRpcInvalidRequest => 'Requisição inválida. Revise os dados enviados.';

  @override
  String get msgRpcMethodNotFound => 'Método não suportado por esta versão do agente.';

  @override
  String get msgRpcAuthenticationFailed => 'Falha de autenticação. Gere um novo token e tente novamente.';

  @override
  String get msgRpcUnauthorized => 'Você não tem permissão para executar esta operação.';

  @override
  String get msgRpcTimeout => 'A operação excedeu o tempo limite. Tente novamente.';

  @override
  String get msgRpcInvalidPayload => 'Falha ao processar os dados da requisição.';

  @override
  String get msgRpcNetworkError => 'Conexão com o hub foi perdida. Tente novamente.';

  @override
  String get msgRpcRateLimited => 'Muitas requisições em pouco tempo. Aguarde e tente novamente.';

  @override
  String get msgRpcReplayDetected => 'Requisição duplicada detectada. Gere um novo ID e tente novamente.';

  @override
  String get msgRpcSqlValidationFailed => 'Comando SQL inválido. Revise a consulta enviada.';

  @override
  String get msgRpcSqlExecutionFailed => 'Falha ao executar o comando SQL.';

  @override
  String get msgRpcConnectionPoolExhausted => 'Limite de conexões atingido. Aguarde e tente novamente.';

  @override
  String get msgRpcResultTooLarge => 'Resultado muito grande. Aplique filtros e tente novamente.';

  @override
  String get msgRpcDatabaseConnectionFailed => 'Não foi possível conectar ao banco de dados.';

  @override
  String get msgRpcInvalidDatabaseConfig => 'Configuração do banco inválida. Revise os dados de conexão.';

  @override
  String get msgRpcExecutionNotFound => 'Execução não encontrada. Pode ter sido finalizada ou nunca iniciada.';

  @override
  String get msgRpcExecutionCancelled => 'Execução cancelada pelo usuário.';

  @override
  String get msgRpcInternalError => 'Falha interna no processamento da requisição.';

  @override
  String get tabWebSocketConnection => 'Conexão WebSocket';

  @override
  String get tabClientTokenAuthorization => 'Autorização de token do cliente';

  @override
  String get tabWebSocketDiagnostics => 'Diagnóstico';

  @override
  String get wsSectionConnection => 'Conexão WebSocket';

  @override
  String get wsSectionOptionalAuth => 'Autenticação (opcional)';

  @override
  String get wsFieldServerUrl => 'URL do servidor';

  @override
  String get wsFieldAgentId => 'ID do agente';

  @override
  String get wsFieldUsername => 'Usuário';

  @override
  String get wsHintServerUrl => 'https://api.example.com';

  @override
  String get wsHintAgentId => 'Gerado automaticamente (somente leitura)';

  @override
  String get wsHintUsername => 'Usuário para autenticação';

  @override
  String get wsHintPassword => 'Senha para autenticação';

  @override
  String get wsButtonAuthenticating => 'Autenticando...';

  @override
  String get wsButtonLogout => 'Logout';

  @override
  String get wsButtonLogin => 'Login';

  @override
  String get wsButtonDisconnect => 'Desconectar';

  @override
  String get wsButtonConnect => 'Conectar';

  @override
  String get wsButtonSaveConfig => 'Salvar configuração';

  @override
  String get wsSectionOutboundCompression => 'Compressão de envio (agente → hub)';

  @override
  String get wsFieldOutboundCompressionMode => 'Modo';

  @override
  String get wsOutboundCompressionOff => 'Desligado';

  @override
  String get wsOutboundCompressionGzip => 'Sempre GZIP';

  @override
  String get wsOutboundCompressionAuto => 'Automático';

  @override
  String get wsOutboundCompressionDescription =>
      'Automático: acima do limite negociado, o agente comprime com GZIP apenas se o resultado for menor que o JSON em UTF-8 (evita CPU e tráfego em dados pouco compressíveis).';

  @override
  String get wsSectionClientTokenPolicy => 'Política de client token (RPC)';

  @override
  String get wsFieldClientTokenPolicyIntrospection => 'Permitir introspecção client_token.getPolicy';

  @override
  String get wsClientTokenPolicyIntrospectionDescription =>
      'Desligado: o hub não pode chamar client_token.getPolicy para ler metadados de permissões; a autorização SQL com client_token não é afetada.';

  @override
  String get dbSectionTitle => 'Configuração do banco de dados';

  @override
  String get dbFieldDatabaseDriver => 'Driver do banco de dados';

  @override
  String get dbFieldOdbcDriverName => 'Nome do driver ODBC';

  @override
  String get dbFieldHost => 'Host';

  @override
  String get dbHintHost => 'localhost';

  @override
  String get dbFieldPort => 'Porta';

  @override
  String get dbHintPort => '1433';

  @override
  String get dbFieldDatabaseName => 'Nome do banco de dados';

  @override
  String get dbHintDatabaseName => 'Nome da base';

  @override
  String get dbFieldUsername => 'Usuário';

  @override
  String get dbHintUsername => 'Usuário';

  @override
  String get dbHintPassword => 'Senha';

  @override
  String get dbButtonTestConnection => 'Testar conexão com banco';

  @override
  String get dbTabDatabase => 'Banco de dados';

  @override
  String get dbTabAdvanced => 'Avançado';

  @override
  String get odbcErrorPoolRange => 'Tamanho do pool deve ser entre 1 e 20';

  @override
  String get odbcErrorLoginTimeoutRange => 'Login timeout deve ser entre 1 e 120 segundos';

  @override
  String get odbcErrorBufferRange => 'Buffer de resultados deve ser entre 8 e 128 MB';

  @override
  String get odbcErrorChunkRange => 'Chunk do streaming deve ser entre 64 e 8192 KB';

  @override
  String get odbcErrorSaveFailed => 'Falha ao salvar configurações avançadas. Tente novamente.';

  @override
  String get odbcSuccessAppliedNow =>
      'As configurações de pool, timeout e streaming foram salvas e aplicadas para novas conexões.';

  @override
  String get odbcSuccessAppliedGradually =>
      'As configurações de pool, timeout e streaming foram salvas. As novas opções serão aplicadas gradualmente em novas conexões.';

  @override
  String get odbcSuccessPoolModeRestartAppend => ' Reinicie o aplicativo para aplicar a troca do modo de pool ODBC.';

  @override
  String get odbcModalTitleSaved => 'Configurações salvas';

  @override
  String get odbcSectionTitle => 'Pool de conexões e timeouts';

  @override
  String get odbcBlockPool => 'Pool de conexões';

  @override
  String get odbcBlockPoolDescription =>
      'Múltiplas conexões são reutilizadas automaticamente. Melhora performance em cenários de alta concorrência.';

  @override
  String get odbcFieldPoolSize => 'Tamanho máximo do pool';

  @override
  String get odbcHintPoolSize => '4';

  @override
  String get odbcFieldNativePool => 'Pool nativo ODBC (experimental)';

  @override
  String get odbcTextNativePoolHelp =>
      'Desligado por padrão: cada consulta usa conexão dedicada com buffer configurado (mais estável). Ative apenas para testar desempenho ou quando o driver/pacote tratar buffers no pool nativo. Após alterar, reinicie o aplicativo para o modo valer de fato.';

  @override
  String get odbcFieldNativePoolCheckoutValidation => 'Validar conexão ao retirar do pool nativo';

  @override
  String get odbcTextNativePoolCheckoutValidationHelp =>
      'Ligado por padrão. Desative apenas para benchmark ou tuning avançado quando quiser comparar o custo do checkout validation do driver.';

  @override
  String get odbcBlockTimeouts => 'Timeouts';

  @override
  String get odbcFieldLoginTimeout => 'Login timeout (segundos)';

  @override
  String get odbcHintLoginTimeout => '30';

  @override
  String get odbcFieldResultBuffer => 'Buffer de resultados (MB)';

  @override
  String get odbcHintResultBuffer => '32';

  @override
  String get odbcTextResultBufferHelp =>
      'Tamanho máximo do buffer em memória para resultados de queries. Aumentar pode melhorar performance em queries grandes.';

  @override
  String get odbcBlockStreaming => 'Streaming';

  @override
  String get odbcFieldChunkSize => 'Tamanho do chunk (KB)';

  @override
  String get odbcHintChunkSize => '1024';

  @override
  String get odbcTextStreamingHelp =>
      'Controla o tamanho dos chunks enviados para a UI durante queries em streaming. Valores maiores reduzem eventos de atualização e podem melhorar throughput.';

  @override
  String get odbcTextQuickRecommendation => 'Recomendação rápida:';

  @override
  String get odbcTextQuickRecommendationItems =>
      '• 256-512 KB: feedback visual mais frequente\n• 1024 KB: equilíbrio geral (padrão)\n• 2048-4096 KB: maior throughput em datasets grandes';

  @override
  String get odbcTextChunkWarning => 'Se houver travamentos de UI ou uso alto de memória, reduza o chunk.';

  @override
  String get odbcButtonRestoreDefault => 'Restaurar padrão';

  @override
  String get odbcButtonSaveAdvanced => 'Salvar configurações avançadas';

  @override
  String get ctSectionTitle => 'Autorização de token do cliente';

  @override
  String get ctFieldClientId => 'Client ID (gerado automaticamente)';

  @override
  String get ctFieldAgentIdOptional => 'Agent ID (opcional)';

  @override
  String get ctFieldPayloadJsonOptional => 'Payload JSON (opcional)';

  @override
  String get ctHintClientId => 'Gerado automaticamente';

  @override
  String get ctHintAgentId => 'agent-01';

  @override
  String get ctHintPayloadJson => 'Objeto JSON (ex.: display_name, env)';

  @override
  String get ctFlagAllTables => 'all_tables';

  @override
  String get ctFlagAllViews => 'all_views';

  @override
  String get ctFlagAllPermissions => 'all_permissions';

  @override
  String get ctSectionRulesByResource => 'Regras por recurso';

  @override
  String get ctRuleTitlePrefix => 'Regra';

  @override
  String get ctButtonAddRule => 'Adicionar regra';

  @override
  String get ctButtonCreateToken => 'Criar token';

  @override
  String get ctButtonNewToken => 'Novo token';

  @override
  String get ctButtonRefreshList => 'Atualizar lista';

  @override
  String get ctButtonAutoRefreshOn => 'Auto refresh: ligado';

  @override
  String get ctButtonAutoRefreshOff => 'Auto refresh: desligado';

  @override
  String get ctButtonViewDetails => 'Ver detalhes';

  @override
  String get ctButtonCopyClientToken => 'Copiar token';

  @override
  String get ctTooltipCopyClientToken => 'Copiar token do cliente';

  @override
  String get ctInfoClientTokenCopied => 'Token do cliente copiado';

  @override
  String get ctInfoClientTokenUnavailable =>
      'Token indisponivel para este registro. Gere um novo token para copiar o valor secreto.';

  @override
  String get ctButtonEdit => 'Editar';

  @override
  String get ctButtonClearFilters => 'Limpar filtros';

  @override
  String get ctSectionRegisteredTokens => 'Tokens cadastrados';

  @override
  String get ctMsgNoTokenFound => 'Nenhum token encontrado.';

  @override
  String get ctMsgNoTokenMatchFilter => 'Nenhum token corresponde aos filtros aplicados.';

  @override
  String get ctFilterClientId => 'Filtrar por Client ID';

  @override
  String get ctFilterStatus => 'Filtrar por status';

  @override
  String get ctFilterSort => 'Ordenar por';

  @override
  String get ctFilterStatusAll => 'Todos';

  @override
  String get ctFilterStatusActive => 'Ativos';

  @override
  String get ctFilterStatusRevoked => 'Revogados';

  @override
  String get ctSortNewest => 'Mais novos';

  @override
  String get ctSortOldest => 'Mais antigos';

  @override
  String get ctSortClientAsc => 'Client A-Z';

  @override
  String get ctSortClientDesc => 'Client Z-A';

  @override
  String get ctMsgTokenCreatedCopyNow => 'Token criado com sucesso (copie e guarde agora):';

  @override
  String get ctLabelClient => 'Client';

  @override
  String get ctLabelId => 'ID';

  @override
  String get ctLabelAgent => 'Agent';

  @override
  String get ctLabelCreatedAt => 'Criado em';

  @override
  String get ctLabelStatus => 'Status';

  @override
  String get ctLabelScope => 'Escopo';

  @override
  String get ctLabelRules => 'Regras';

  @override
  String get ctLabelPayload => 'Payload';

  @override
  String get ctScopeAllPermissions => 'Todas as permissões';

  @override
  String get ctScopeRestricted => 'Permissões restritas';

  @override
  String get ctScopeTables => 'Tabelas';

  @override
  String get ctScopeViews => 'Views';

  @override
  String get ctScopeNotInformed => 'não informado pela API';

  @override
  String get ctStatusRevoked => 'revogado';

  @override
  String get ctStatusActive => 'ativo';

  @override
  String get ctButtonRevoked => 'Revogado';

  @override
  String get ctButtonRevoke => 'Revogar';

  @override
  String get ctButtonDelete => 'Excluir';

  @override
  String get ctConfirmRevokeTitle => 'Revogar token';

  @override
  String get ctConfirmRevokeMessage =>
      'Tem certeza que deseja revogar este token? O token deixará de funcionar imediatamente.';

  @override
  String get ctConfirmDeleteTitle => 'Excluir token';

  @override
  String get ctConfirmDeleteMessage => 'Tem certeza que deseja excluir este token? Esta ação não pode ser desfeita.';

  @override
  String get ctErrorRuleOrAllPermissionsRequired => 'Adicione ao menos uma regra valida ou marque all_permissions.';

  @override
  String get ctErrorPayloadMustBeJsonObject => 'Payload deve ser um objeto JSON valido.';

  @override
  String get ctErrorPayloadInvalidJson => 'Payload JSON invalido.';

  @override
  String get ctPermissionRead => 'Read';

  @override
  String get ctPermissionUpdate => 'Update';

  @override
  String get ctPermissionDelete => 'Delete';

  @override
  String get ctGridColumnType => 'Tipo';

  @override
  String get ctGridColumnResource => 'Recurso';

  @override
  String get ctGridColumnEffect => 'Efeito';

  @override
  String get ctGridColumnPermissions => 'Permissões';

  @override
  String get ctGridColumnActions => 'Ações';

  @override
  String get ctNoRulesAdded => 'Nenhuma regra adicionada. Clique em \"Adicionar regra\".';

  @override
  String get ctDialogAddRuleTitle => 'Adicionar regra';

  @override
  String get ctDialogCreateTokenTitle => 'Criar token do cliente';

  @override
  String get ctDialogEditTokenTitle => 'Editar token do cliente';

  @override
  String get ctButtonSaveTokenChanges => 'Salvar alterações';

  @override
  String get ctDialogEditRuleTitle => 'Editar regra';

  @override
  String get ctDialogSaveRule => 'Salvar regra';

  @override
  String get ctEditUpdatesTokenHint => 'As alteracoes serao aplicadas ao token selecionado.';

  @override
  String get ctDialogTokenDetailsTitle => 'Detalhes do token';

  @override
  String get ctRuleNoPermission => 'Sem permissões';

  @override
  String get ctTooltipEditRule => 'Editar regra';

  @override
  String get ctTooltipDeleteRule => 'Excluir regra';

  @override
  String get ctTooltipEditToken => 'Editar token';

  @override
  String get ctErrorRuleResourceRequired => 'Informe ao menos um recurso (schema.nome).';

  @override
  String get ctErrorRulePermissionRequired => 'Selecione ao menos uma permissão para a regra.';

  @override
  String ctErrorRuleResourceInvalidChars(String resource) {
    return 'Nome de recurso inválido: \"$resource\". Use apenas letras, números, underscores e um ponto opcional (schema.nome).';
  }

  @override
  String ctRuleWarnDuplicates(String resources) {
    return 'As regras a seguir já existem e serão substituídas: $resources. Confirme para continuar.';
  }

  @override
  String get ctDialogConfirmReplace => 'Confirmar substituição';

  @override
  String get ctRuleImportFile => 'Importar .txt';

  @override
  String get ctButtonExportRules => 'Exportar regras';

  @override
  String get ctButtonImportRules => 'Importar regras';

  @override
  String get ctExportRulesDefaultFileName => 'regras_token.txt';

  @override
  String ctImportRulesErrorInvalidFormat(int line, String content) {
    return 'Linha $line: \"$content\" — formato inválido. Cada linha deve estar no padrão completo: recurso;tipo;efeito;permissões (ex: dbo.clientes;table;allow;read).';
  }

  @override
  String get ctImportRulesErrorEmpty => 'O arquivo está vazio ou não contém regras válidas.';

  @override
  String get ctImportRulesErrorFileTooLarge => 'O arquivo excede o tamanho máximo permitido (512 KB).';

  @override
  String ctImportRulesSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regras importadas com sucesso.',
      one: '1 regra importada com sucesso.',
    );
    return '$_temp0';
  }

  @override
  String ctRuleImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regras importadas com sucesso.',
      one: '1 regra importada com sucesso.',
    );
    return '$_temp0';
  }

  @override
  String get ctRuleImportErrorEmpty => 'O arquivo está vazio.';

  @override
  String get ctRuleImportErrorNoValidLines => 'Nenhuma linha válida encontrada no arquivo.';

  @override
  String get ctRuleImportErrorFileTooLarge => 'O arquivo excede o tamanho máximo permitido (512 KB).';

  @override
  String ctRuleImportErrorLineInvalid(int line, String content) {
    return 'Linha $line: \"$content\" — formato inválido. Use schema.nome ou schema.nome;table;allow;read.';
  }

  @override
  String get ctRuleFieldType => 'Tipo';

  @override
  String get ctRuleFieldEffect => 'Efeito';

  @override
  String get ctRuleFieldResource => 'Recurso (schema.nome)';

  @override
  String get ctRuleHintResource => 'dbo.clientes; dbo.pedidos';

  @override
  String get ctLabelPayloadColon => 'Payload:';

  @override
  String get ctLabelRulesColon => 'Regras:';

  @override
  String get ctRuleFieldEffectColon => 'Efeito:';

  @override
  String get ctGridColumnPermissionsColon => 'Permissões:';

  @override
  String get connectionStatusHubConnected => 'Hub: Conectado';

  @override
  String get connectionStatusHubConnecting => 'Hub: Conectando...';

  @override
  String get connectionStatusHubReconnecting => 'Hub: Reconectando...';

  @override
  String get connectionStatusHubError => 'Hub: Erro de conexão';

  @override
  String get connectionStatusHubDisconnected => 'Hub: Desconectado';

  @override
  String get msgHubPersistentRetryExhausted =>
      'Não foi possível alcançar o hub após várias tentativas. Verifique a URL do servidor, a rede e o login e toque em Conectar.';

  @override
  String get connectionStatusDatabaseConnected => 'BD: Conectado';

  @override
  String get connectionStatusDatabaseDisconnected => 'BD: Desconectado';

  @override
  String get connectionStatusDatabaseTooltip =>
      'Última verificação ODBC bem-sucedida (teste de conexão ou consulta). Não indica uma sessão permanente com o banco.';

  @override
  String get formHintCep => '00.000-000';

  @override
  String get formHintPhone => '(00) 0000-0000';

  @override
  String get formHintMobile => '(00) 00000-0000';

  @override
  String get formHintDocument => '000.000.000-00 ou 00.000.000/0000-00';

  @override
  String get formHintState => 'SP';

  @override
  String get formValidationEmailInvalid => 'E-mail inválido';

  @override
  String get formValidationUrlHttpHttps => 'Informe uma URL com http:// ou https://';

  @override
  String get formValidationCepDigits => 'CEP deve ter 8 dígitos';

  @override
  String get formValidationPhoneDigits => 'Telefone deve ter 10 dígitos (DDD + número)';

  @override
  String get formValidationMobileDigits => 'Celular deve ter 11 dígitos';

  @override
  String get formValidationMobileNineAfterDdd => 'Celular deve começar com 9 após o DDD';

  @override
  String get formValidationDocumentDigits => 'CPF (11) ou CNPJ (14) dígitos';

  @override
  String get formValidationStateLetters => 'UF com 2 letras';

  @override
  String get formFieldLabelPassword => 'Senha';

  @override
  String get formPasswordDefaultHint => 'Digite a senha';

  @override
  String formPasswordRequired(String fieldLabel) {
    return '$fieldLabel é obrigatória.';
  }

  @override
  String get formNumericInvalidValue => 'Valor inválido';

  @override
  String formNumericMinValue(int min) {
    return 'Valor mínimo: $min';
  }

  @override
  String formNumericMaxValue(int max) {
    return 'Valor máximo: $max';
  }
}

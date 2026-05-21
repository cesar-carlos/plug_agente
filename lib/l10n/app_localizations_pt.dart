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
  String get navAgentActions => 'Acoes do Sistema';

  @override
  String get agentActionsRefresh => 'Atualizar';

  @override
  String get agentActionsRunSelected => 'Executar selecionada';

  @override
  String get agentActionsTestSelected => 'Testar acao';

  @override
  String get agentActionsCancelExecution => 'Cancelar execucao';

  @override
  String get agentActionsDeleteSelected => 'Excluir acao';

  @override
  String get agentActionsDeleteConfirmTitle => 'Excluir acao';

  @override
  String agentActionsDeleteConfirmMessage(Object actionName) {
    return 'Excluir \"$actionName\"? O historico de execucao sera preservado, mas esta acao nao podera mais executar.';
  }

  @override
  String get agentActionsDeleteConfirm => 'Excluir';

  @override
  String get agentActionsDeleteCancel => 'Cancelar';

  @override
  String get agentActionsExportBundle => 'Exportar acoes…';

  @override
  String get agentActionsImportBundle => 'Importar acoes…';

  @override
  String get agentActionsExportBundleDefaultFileName => 'plug_agente_acoes.json';

  @override
  String get agentActionsExportBundleSuccessTitle => 'Acoes exportadas';

  @override
  String get agentActionsExportBundleSuccessMessage =>
      'O pacote sanitizado foi salvo. Valores de segredo nao foram incluidos; configure os placeholders na maquina de destino.';

  @override
  String get agentActionsImportBundleSuccessTitle => 'Acoes importadas';

  @override
  String agentActionsImportBundleSuccessMessage(int definitionCount, int triggerCount) {
    String _temp0 = intl.Intl.pluralLogic(
      definitionCount,
      locale: localeName,
      other: '$definitionCount acoes',
      one: '1 acao',
    );
    String _temp1 = intl.Intl.pluralLogic(
      triggerCount,
      locale: localeName,
      other: '$triggerCount gatilhos',
      one: '1 gatilho',
    );
    return 'Importadas $_temp0 e $_temp1. Valide as definicoes antes de executar.';
  }

  @override
  String agentActionsImportBundleSecretsMessage(Object secretNames) {
    return 'Configure estes placeholders de segredo nesta maquina: $secretNames.';
  }

  @override
  String get agentActionsConfirmImportBundleTitle => 'Importar acoes';

  @override
  String get agentActionsConfirmImportBundleMessage =>
      'Importar acoes de um pacote JSON? Acoes existentes com o mesmo id serao atualizadas. Gatilhos entram pausados e execucao remota exige nova aprovacao.';

  @override
  String get agentActionsConfirmImportBundleConfirm => 'Importar';

  @override
  String get agentActionsConfirmImportBundleCancel => 'Cancelar';

  @override
  String get agentActionsBundleTransferFailedTitle => 'Falha na transferencia do pacote de acoes';

  @override
  String get agentActionsBundlePickerError => 'Nao foi possivel abrir o seletor de arquivos.';

  @override
  String get agentActionsTestSuccessTitle => 'Teste da acao concluido';

  @override
  String get agentActionsTestCanRunMessage => 'A configuracao da acao e valida e a acao pode executar.';

  @override
  String get agentActionsTestValidButInactiveMessage => 'A configuracao da acao e valida, mas a acao nao esta ativa.';

  @override
  String get agentActionsTestPreviewTitle => 'Preview redigido do teste';

  @override
  String get agentActionsTestPreviewCommandLabel => 'Comando preparado';

  @override
  String get agentActionsTestPreviewUnavailableTitle => 'Preview indisponivel';

  @override
  String get agentActionsTestPreviewDiagnosticEngine => 'Engine';

  @override
  String get agentActionsTestPreviewDiagnosticConnectionLabel => 'Conexao';

  @override
  String get agentActionsTestPreviewDiagnosticCatalogCount => 'Conexoes no catalogo';

  @override
  String get agentActionsTestPreviewDiagnosticDefaultConfig => 'Usou config padrao';

  @override
  String get agentActionsTestPreviewDiagnosticYes => 'Sim';

  @override
  String get agentActionsTestPreviewDiagnosticNo => 'Nao';

  @override
  String get agentActionsFormCreateTitle => 'Nova acao de linha de comando';

  @override
  String get agentActionsFormEditTitle => 'Acao de linha de comando';

  @override
  String get agentActionsFormCreateDeveloperTitle => 'Nova acao developer';

  @override
  String get agentActionsFormEditDeveloperTitle => 'Acao developer';

  @override
  String get agentActionsFormCreateExecutableTitle => 'Nova acao executavel';

  @override
  String get agentActionsFormEditExecutableTitle => 'Acao executavel';

  @override
  String get agentActionsFormExecutablePath => 'Caminho do executavel';

  @override
  String get agentActionsFormArguments => 'Argumentos';

  @override
  String get agentActionsFormArgumentsHint => 'Informe um argumento por linha.';

  @override
  String get agentActionsFormBrowseExecutablePath => 'Procurar executavel';

  @override
  String get agentActionsFormCreateScriptTitle => 'Nova acao de script';

  @override
  String get agentActionsFormEditScriptTitle => 'Acao de script';

  @override
  String get agentActionsFormScriptPath => 'Caminho do script';

  @override
  String get agentActionsFormInterpreterPath => 'Caminho do interpretador (opcional)';

  @override
  String get agentActionsFormInterpreterPathHint =>
      'Deixe vazio para usar o interpretador padrao da extensao do script.';

  @override
  String get agentActionsFormBrowseScriptPath => 'Procurar script';

  @override
  String get agentActionsFormBrowseInterpreterPath => 'Procurar interpretador';

  @override
  String get agentActionsFormCreateJarTitle => 'Nova acao JAR';

  @override
  String get agentActionsFormEditJarTitle => 'Acao JAR';

  @override
  String get agentActionsFormJarPath => 'Caminho do arquivo .jar';

  @override
  String get agentActionsFormJavaExecutablePath => 'Caminho do java.exe (opcional)';

  @override
  String get agentActionsFormJavaExecutablePathHint => 'Deixe vazio para usar o java.exe do PATH.';

  @override
  String get agentActionsFormBrowseJarPath => 'Procurar arquivo .jar';

  @override
  String get agentActionsFormBrowseJavaExecutablePath => 'Procurar java.exe';

  @override
  String get agentActionsFormCreateEmailTitle => 'Nova acao de e-mail';

  @override
  String get agentActionsFormEditEmailTitle => 'Acao de e-mail';

  @override
  String get agentActionsFormSmtpProfileId => 'Nome do segredo do perfil SMTP';

  @override
  String get agentActionsFormSmtpProfileIdHint => 'Nome do segredo que armazena o JSON do perfil SMTP.';

  @override
  String get agentActionsFormEmailFrom => 'Remetente';

  @override
  String get agentActionsFormEmailTo => 'Destinatarios (Para)';

  @override
  String get agentActionsFormEmailToHint => 'Um endereco de e-mail por linha.';

  @override
  String get agentActionsFormEmailCc => 'Copia (Cc) opcional';

  @override
  String get agentActionsFormEmailCcHint => 'Um endereco de e-mail por linha.';

  @override
  String get agentActionsFormEmailBcc => 'Copia oculta (Cco) opcional';

  @override
  String get agentActionsFormEmailBccHint => 'Um endereco de e-mail por linha.';

  @override
  String get agentActionsFormEmailSubject => 'Modelo do assunto';

  @override
  String get agentActionsFormEmailSubjectHint =>
      'Use tokens de contexto resolvidos pelo arquivo JSON de contexto opcional.';

  @override
  String get agentActionsFormEmailBody => 'Modelo do corpo';

  @override
  String get agentActionsFormEmailBodyHint =>
      'Corpo em texto simples. Use tokens de contexto resolvidos pelo arquivo JSON de contexto opcional.';

  @override
  String get agentActionsFormEmailAttachments => 'Caminhos dos anexos (opcional)';

  @override
  String get agentActionsFormEmailAttachmentsHint =>
      'Um caminho de arquivo por linha. Os tipos permitidos sao validados pela politica da acao.';

  @override
  String get agentActionsFormCreateComObjectTitle => 'Nova acao de objeto COM';

  @override
  String get agentActionsFormEditComObjectTitle => 'Acao de objeto COM';

  @override
  String get agentActionsFormComProgId => 'ProgID COM';

  @override
  String get agentActionsFormComMemberName => 'Membro COM';

  @override
  String get agentActionsFormComArguments => 'Argumentos (objeto JSON)';

  @override
  String get agentActionsFormComArgumentsHint => 'Use um objeto JSON simples com valores texto, numero ou booleano.';

  @override
  String get agentActionsFormInvalidComArguments => 'Os argumentos precisam ser um objeto JSON valido.';

  @override
  String get agentActionsFormNew => 'Nova';

  @override
  String get agentActionsFormSave => 'Salvar acao';

  @override
  String get agentActionsFormName => 'Nome';

  @override
  String get agentActionsFormDescription => 'Descricao';

  @override
  String get agentActionsFormType => 'Tipo';

  @override
  String get agentActionsFormCommand => 'Comando';

  @override
  String get agentActionsFormWorkingDirectory => 'Diretorio de trabalho';

  @override
  String get agentActionsFormExecutorPath => 'Caminho do Executor.exe';

  @override
  String get agentActionsFormProjectPath => 'Caminho do arquivo .7Proj';

  @override
  String get agentActionsFormData7ConfigPath => 'Caminho do Data7.Config';

  @override
  String get agentActionsFormBrowseExecutorPath => 'Localizar Executor.exe';

  @override
  String get agentActionsFormBrowseProjectPath => 'Localizar arquivo .7Proj';

  @override
  String get agentActionsFormBrowseData7ConfigPath => 'Localizar Data7.Config';

  @override
  String get agentActionsFormBrowseFileError => 'Nao foi possivel abrir o seletor de arquivo desta acao.';

  @override
  String get agentActionsFormUseDefaultExecutorPath => 'Usar Executor padrao';

  @override
  String get agentActionsFormUseDefaultConfigBinPath => 'Usar config padrao (bin)';

  @override
  String get agentActionsFormUseDefaultConfigRootPath => 'Usar config padrao (raiz)';

  @override
  String get agentActionsFormExecutorPathHintExpectedFileName => 'O caminho do executor deve terminar em Executor.exe.';

  @override
  String get agentActionsFormExecutorPathHintDefault => 'O executor esta apontando para o caminho padrao do Data7.';

  @override
  String get agentActionsFormExecutorPathHintMissing => 'O Executor.exe informado nao foi encontrado neste caminho.';

  @override
  String get agentActionsFormExecutorPathHintDirectory =>
      'O caminho do executor aponta para uma pasta, nao para um arquivo Executor.exe.';

  @override
  String get agentActionsFormProjectPathHintExpectedExtension => 'O projeto deve apontar para um arquivo .7Proj.';

  @override
  String get agentActionsFormProjectPathHintMissing => 'O arquivo .7Proj informado nao foi encontrado neste caminho.';

  @override
  String get agentActionsFormProjectPathHintDirectory =>
      'O caminho do projeto aponta para uma pasta, nao para um arquivo .7Proj.';

  @override
  String get agentActionsFormData7ConfigPathHintExpectedFileName =>
      'O caminho de configuracao deve terminar em Data7.Config.';

  @override
  String get agentActionsFormData7ConfigPathHintDefaultBin =>
      'O Data7.Config esta apontando para o caminho padrao em C:\\Data7\\bin.';

  @override
  String get agentActionsFormData7ConfigPathHintDefaultRoot =>
      'O Data7.Config esta apontando para o caminho padrao em C:\\Data7.';

  @override
  String get agentActionsFormData7ConfigPathHintMissing => 'O Data7.Config informado nao foi encontrado neste caminho.';

  @override
  String get agentActionsFormData7ConfigPathHintDirectory =>
      'O caminho de configuracao aponta para uma pasta, nao para um arquivo Data7.Config.';

  @override
  String get agentActionsFormPathHintInspectionFailed =>
      'Nao foi possivel inspecionar este caminho local agora. Revise permissao, link ou disponibilidade do disco.';

  @override
  String get agentActionsFormReloadConnections => 'Recarregar conexoes';

  @override
  String get agentActionsFormDefaultConfigResolved => 'Usando o Data7.Config encontrado no local padrao.';

  @override
  String agentActionsFormResolvedConfigPath(Object path) {
    return 'Config resolvido: $path';
  }

  @override
  String agentActionsFormLoadedConfigPath(Object path) {
    return 'Conexoes carregadas de: $path';
  }

  @override
  String get agentActionsFormConnectionId => 'ID da conexao';

  @override
  String get agentActionsFormConnectionSelector => 'Conexao carregada';

  @override
  String get agentActionsFormConnectionSelectorPlaceholder => 'Selecione uma conexao carregada';

  @override
  String get agentActionsFormConnectionSearch => 'Filtrar conexoes carregadas';

  @override
  String get agentActionsFormConnectionFilterEmpty => 'Nenhuma conexao carregada corresponde a este filtro.';

  @override
  String get agentActionsFormConnectionLabel => 'Rotulo seguro da conexao';

  @override
  String get agentActionsFormConnectionMissingTitle => 'Conexao salva nao encontrada';

  @override
  String get agentActionsFormConnectionMissingMessage =>
      'A conexao salva nao existe mais no Data7.Config carregado. Recarregue as conexoes, selecione outra conexao valida e salve a acao novamente.';

  @override
  String get agentActionsFormConnectionUnknownTitle => 'ID de conexao fora do catalogo carregado';

  @override
  String get agentActionsFormConnectionUnknownMessage =>
      'O ID informado nao pertence ao catalogo carregado agora. Selecione uma conexao valida na lista ou recarregue as conexoes antes de salvar.';

  @override
  String get agentActionsFormConnectionChangedTitle => 'Conexao alterada desde a ultima validacao';

  @override
  String get agentActionsFormConnectionChangedMessage =>
      'A conexao carregada mudou desde o snapshot salvo. Revise a configuracao e salve a acao novamente antes de executar.';

  @override
  String get agentActionsFormUnsupportedType =>
      'O editor visual deste tipo de acao ainda nao esta disponivel nesta tela.';

  @override
  String get agentActionsFormState => 'Estado';

  @override
  String get agentActionsFormNotificationsTitle => 'Notificacoes desktop';

  @override
  String get agentActionsFormNotificationsDescription =>
      'Exibe uma notificacao do Windows quando uma execucao local atinge um estado terminal.';

  @override
  String get agentActionsFormNotifyOnSuccess => 'Notificar em sucesso';

  @override
  String get agentActionsFormNotifyOnFailure => 'Notificar em falha';

  @override
  String get agentActionsFormNotifyOnTimeout => 'Notificar em timeout';

  @override
  String get agentActionNotificationSuccessBody => 'Execucao concluida com sucesso.';

  @override
  String get agentActionNotificationTimeoutBody => 'Execucao excedeu o tempo maximo configurado.';

  @override
  String get agentActionNotificationFailureFallbackBody => 'Execucao terminou com falha.';

  @override
  String get agentActionsFormExecutionPoliciesTitle => 'Politicas de execucao';

  @override
  String get agentActionsFormExecutionPoliciesDescription =>
      'Timeout e retry valem para execucoes locais e gatilhos. Execucoes remotas do Hub permanecem em uma tentativa, salvo se retry remoto estiver habilitado.';

  @override
  String get agentActionsFormPathChangePolicy => 'Politica de mudanca de path';

  @override
  String get agentActionsFormPathChangePolicyFail => 'Falhar se path ou conteudo mudou';

  @override
  String get agentActionsFormPathChangePolicyWarn => 'Avisar se path ou conteudo mudou';

  @override
  String get agentActionsFormPathChangePolicyAllow => 'Permitir mudancas de path e conteudo';

  @override
  String get agentActionsFormContextInjectionMode => 'Modo de injecao de contexto';

  @override
  String get agentActionsFormContextInjectionArgument => 'Argumento (padrao)';

  @override
  String get agentActionsFormContextInjectionFile => 'Arquivo de contexto (obrigatorio na execucao)';

  @override
  String get agentActionsFormContextInjectionEnvironment => 'Variaveis de ambiente';

  @override
  String get agentActionsFormContextInjectionStdin => 'Entrada padrao (stdin)';

  @override
  String get agentActionsFormRuntimeParameterSchema => 'Schema JSON de parametros runtime (opcional)';

  @override
  String get agentActionsFormRuntimeParameterSchemaHint =>
      'Objeto JSON Schema validado contra runtimeParameters em cada execucao. Deixe vazio para ignorar.';

  @override
  String get agentActionsTestPreviewPathSnapshotWarnings => 'Avisos de snapshot de path';

  @override
  String get agentActionsFormMaxRuntimeMinutes => 'Tempo maximo (minutos)';

  @override
  String get agentActionsFormKillOnTimeout => 'Encerrar processo principal no timeout';

  @override
  String get agentActionsFormMaxAttempts => 'Maximo de tentativas';

  @override
  String get agentActionsFormAllowRemoteRetry => 'Permitir retry em execucoes remotas do Hub';

  @override
  String get agentActionsFormRuntimePoliciesTitle => 'Restricoes de runtime';

  @override
  String get agentActionsFormRuntimePoliciesDescription =>
      'Perfil operacional, ambiente do processo filho, codigos de saida aceitos e comportamento ao fechar o Plug Agente. Perfis permitidos vazios significa qualquer perfil.';

  @override
  String get agentActionsFormAllowedProfiles => 'Perfis operacionais permitidos';

  @override
  String get agentActionsFormAllowedProfilesHint =>
      'Separados por virgula (ex.: prod, homolog). Deixe vazio para qualquer perfil.';

  @override
  String get agentActionsFormAllowedEnvironmentVariableNames => 'Nomes de variaveis de ambiente permitidos';

  @override
  String get agentActionsFormAllowedEnvironmentVariableNamesHint =>
      'Separados por virgula (ex.: PLUG_API_URL, PLUG_TOKEN). Deixe vazio para permitir qualquer nome usado abaixo ou em runtime.';

  @override
  String get agentActionsFormEnvironmentVariables => 'Variaveis de ambiente do processo';

  @override
  String get agentActionsFormEnvironmentVariablesHint =>
      'Uma linha NAME=valor. Referencie segredos da acao com o placeholder documentado na secao de segredos. Aplicadas ao iniciar o processo; o modo de injecao por ambiente adiciona parametros runtime da execucao.';

  @override
  String get agentActionsFormEnvironmentVariablesInvalid =>
      'Variaveis de ambiente devem usar uma linha NAME=valor por entrada, com nome valido.';

  @override
  String agentActionsFormCurrentOperationalProfile(String profile) {
    return 'Perfil atual do agente: $profile';
  }

  @override
  String get agentActionsFormCurrentOperationalProfileUnset =>
      'Perfil atual do agente nao definido (AGENT_OPERATIONAL_PROFILE).';

  @override
  String get agentActionsFormAcceptedExitCodes => 'Codigos de saida aceitos';

  @override
  String get agentActionsFormAcceptedExitCodesHint => 'Inteiros separados por virgula (padrao 0).';

  @override
  String get agentActionsFormInvalidExitCodes =>
      'Informe inteiros separados por virgula para os codigos de saida (ex.: 0, 1).';

  @override
  String get agentActionsFormProcessWindowMode => 'Janela do processo';

  @override
  String get agentActionsFormProcessWindowModeNormal => 'Console normal';

  @override
  String get agentActionsFormProcessWindowModeHidden => 'Oculta (melhor esforco)';

  @override
  String get agentActionsFormProcessWindowModeMinimized => 'Minimizada (inicio normal)';

  @override
  String get agentActionsFormCapturePolicyDescription =>
      'Define se a saida do processo sera armazenada e redigida antes da persistencia.';

  @override
  String get agentActionsFormCaptureStdout => 'Capturar stdout';

  @override
  String get agentActionsFormCaptureStderr => 'Capturar stderr';

  @override
  String get agentActionsFormRedactBeforePersisting => 'Redigir saida antes de salvar';

  @override
  String get agentActionsFormQueuePolicyDescription =>
      'Limites de execucao concorrente e comportamento da fila desta definicao.';

  @override
  String get agentActionsFormMaxConcurrent => 'Maximo de execucoes concorrentes';

  @override
  String get agentActionsFormMaxQueued => 'Maximo na fila';

  @override
  String get agentActionsFormInvalidQueueLimits => 'Informe inteiros positivos para concorrencia maxima e fila maxima.';

  @override
  String get agentActionsFormConcurrencyBehavior => 'Quando o limite for atingido';

  @override
  String get agentActionsFormConcurrencyAllowParallel => 'Permitir paralelo (sem limite)';

  @override
  String get agentActionsFormConcurrencyEnqueue => 'Enfileirar e aguardar';

  @override
  String get agentActionsFormConcurrencyReject => 'Rejeitar novas execucoes';

  @override
  String get agentActionsFormConcurrencyIgnore => 'Executar mesmo assim (ignorar limite)';

  @override
  String get agentActionsFormPathAllowlistDescription =>
      'Allowlists opcionais de diretorio. Deixe vazio para validar apenas em runtime.';

  @override
  String get agentActionsFormAllowedWorkingDirectories => 'Diretorios de trabalho permitidos';

  @override
  String get agentActionsFormAllowedContextDirectories => 'Diretorios de contexto permitidos';

  @override
  String get agentActionsFormPathAllowlistHint => 'Caminhos absolutos separados por virgula (ex.: C:\\\\Data7\\\\bin).';

  @override
  String get agentActionsFormOutputEncodingDescription => 'Decodificacao de stdout e stderr capturados na execucao.';

  @override
  String get agentActionsFormStdoutEncoding => 'Encoding de stdout';

  @override
  String get agentActionsFormStderrEncoding => 'Encoding de stderr';

  @override
  String get agentActionsFormOutputEncodingUtf8 => 'UTF-8';

  @override
  String get agentActionsFormOutputEncodingSystemConsole => 'Console do sistema (Windows)';

  @override
  String get agentActionsFormOnAppExit => 'Ao fechar o agente';

  @override
  String get agentActionsFormOnAppExitKill => 'Encerrar processo principal';

  @override
  String get agentActionsFormOnAppExitWaitThenKill => 'Aguardar e encerrar processo principal';

  @override
  String get agentActionsFormOnAppExitLeaveRunning => 'Manter processo em execucao';

  @override
  String get agentActionsFormRemotePoliciesTitle => 'Execucao remota';

  @override
  String get agentActionsFormRemotePoliciesDescription =>
      'Permite que o Hub execute esta acao salva via Socket.IO JSON-RPC. Exige aprovacao local explicita.';

  @override
  String get agentActionsFormRemoteExecutionEnabled => 'Permitir execucao remota do Hub';

  @override
  String get agentActionsFormRemoteAdHocEnabled => 'Permitir comandos remotos ad-hoc';

  @override
  String get agentActionsFormRemoteApprovedHint => 'Execucao remota aprovada para esta definicao.';

  @override
  String get agentActionsFormRemoteApprovalRequired => 'Confirme a execucao remota antes de salvar.';

  @override
  String get agentActionsFormRemoteReapprovalRequiredTitle => 'Reaprovacao remota necessaria';

  @override
  String get agentActionsFormRemoteReapprovalRequiredMessage =>
      'Campos de risco mudaram desde a ultima aprovacao remota. Confirme a execucao remota novamente antes de salvar.';

  @override
  String get agentActionsConfirmRemoteReapprovalTitle => 'Reaprovar execucao remota?';

  @override
  String get agentActionsConfirmRemoteReapprovalMessage =>
      'Comando, caminhos ou politicas de runtime mudaram. O Hub nao pode executar esta acao remotamente ate voce confirmar de novo.';

  @override
  String get agentActionsConfirmRemoteReapprovalConfirm => 'Reaprovar';

  @override
  String get agentActionsConfirmRemoteReapprovalCancel => 'Cancelar';

  @override
  String get agentActionsFormRemoteFeatureDisabledTitle => 'Acoes remotas desativadas';

  @override
  String get agentActionsFormRemoteFeatureDisabledMessage =>
      'Ative a feature flag de acoes remotas antes do Hub chamar agent.action.* neste agente.';

  @override
  String get agentActionsFormRemoteAdHocFeatureDisabledTitle => 'Ad-hoc remoto desativado';

  @override
  String get agentActionsFormRemoteAdHocFeatureDisabledMessage =>
      'Ative a feature flag de ad-hoc remoto para permitir comandos livres pelo hub neste agente.';

  @override
  String get agentActionsRiskRemote => 'Remoto';

  @override
  String get agentActionsRiskRemoteAdHoc => 'Ad-hoc remoto';

  @override
  String get agentActionsRiskRemoteReapproval => 'Reaprovacao necessaria';

  @override
  String get agentActionsRiskAppCloseTrigger => 'Gatilho ao fechar app';

  @override
  String get agentActionsRiskSensitiveOutput => 'Saida sem redacao';

  @override
  String get agentActionsRiskLeaveProcessRunning => 'Mantem processo ativo';

  @override
  String get agentActionsRiskUnsupportedType => 'Editor indisponivel';

  @override
  String get agentActionsRiskNeedsValidation => 'Precisa validar';

  @override
  String get agentActionsRiskSecretPlaceholders => 'Usa segredos';

  @override
  String get agentActionsNeedsValidationTitle => 'Validacao necessaria';

  @override
  String get agentActionsNeedsValidationMessage =>
      'Teste esta acao localmente antes de executar ou habilitar execucao remota.';

  @override
  String get agentActionsSecretPlaceholdersTitle => 'Placeholders de segredo referenciados';

  @override
  String agentActionsSecretPlaceholdersMessage(String secretNames) {
    return 'Esta acao referencia segredos: $secretNames. Configure-os no armazenamento seguro antes de executar.';
  }

  @override
  String get agentActionsMissingSecretsTitle => 'Segredos ausentes';

  @override
  String agentActionsMissingSecretsMessage(String secretNames) {
    return 'Estes segredos nao estao disponiveis localmente: $secretNames.';
  }

  @override
  String get agentActionsSecretsSectionTitle => 'Segredos da acao';

  @override
  String get agentActionsSecretsSectionMessage =>
      'Configure os valores de cada placeholder de segredo referenciado por esta acao. Os valores ficam apenas no armazenamento seguro local.';

  @override
  String get agentActionsSecretStatusConfigured => 'Configurado';

  @override
  String get agentActionsSecretStatusMissing => 'Ausente';

  @override
  String get agentActionsSecretConfigure => 'Configurar';

  @override
  String get agentActionsSecretUpdate => 'Atualizar';

  @override
  String get agentActionsSecretRemove => 'Remover';

  @override
  String agentActionsSecretConfigureTitle(String secretName) {
    return 'Configurar segredo $secretName';
  }

  @override
  String get agentActionsSecretConfigureMessage =>
      'Informe o valor do segredo. Ele nao aparecera na definicao da acao, em logs ou no historico de execucao.';

  @override
  String get agentActionsSecretConfigureValueLabel => 'Valor do segredo';

  @override
  String get agentActionsSecretConfigureValueHint => 'Informe o valor';

  @override
  String get agentActionsSecretConfigureSave => 'Salvar';

  @override
  String get agentActionsSecretConfigureCancel => 'Cancelar';

  @override
  String get agentActionsSecretConfigureErrorTitle => 'Nao foi possivel salvar o segredo';

  @override
  String get agentActionsSecretDeleteTitle => 'Remover segredo?';

  @override
  String agentActionsSecretDeleteMessage(String secretName) {
    return 'Remover o valor local de \"$secretName\"? A acao falhara ate o segredo ser configurado novamente.';
  }

  @override
  String get agentActionsSecretDeleteConfirm => 'Remover';

  @override
  String get agentActionsSecretDeleteCancel => 'Cancelar';

  @override
  String get agentActionsSecretOperationErrorTitle => 'Falha na operacao de segredo';

  @override
  String get agentActionsHistoryFilterSearch => 'Buscar execucao';

  @override
  String get agentActionsRiskRunnerUnavailable => 'Runner indisponivel';

  @override
  String get agentActionsRiskElevated => 'Execucao elevada';

  @override
  String get agentActionsActionTypeUnavailableTitle => 'Runner indisponivel para este tipo';

  @override
  String agentActionsActionTypeUnavailableMessage(String actionType) {
    return 'O subsistema de acoes esta degradado e nao pode executar acoes do tipo $actionType ate o runner ou a capability serem restaurados.';
  }

  @override
  String agentActionsQueueActiveIndicator(int pending, int running) {
    return '$pending na fila · $running em execucao na fila';
  }

  @override
  String get agentActionsConfirmRemoteTitle => 'Habilitar execucao remota?';

  @override
  String get agentActionsConfirmRemoteMessage =>
      'O Hub podera executar esta acao salva quando scopes, policy do token e feature flags permitirem.';

  @override
  String get agentActionsConfirmRemoteConfirm => 'Habilitar remoto';

  @override
  String get agentActionsConfirmRemoteCancel => 'Cancelar';

  @override
  String get agentActionsConfirmRemoteAdHocTitle => 'Habilitar comandos remotos ad-hoc?';

  @override
  String get agentActionsConfirmRemoteAdHocMessage =>
      'Comandos ad-hoc remotos sao de alto risco; mantenha desligado salvo necessidade explicita.';

  @override
  String get agentActionsConfirmRemoteAdHocConfirm => 'Habilitar ad-hoc';

  @override
  String get agentActionsConfirmRemoteAdHocCancel => 'Cancelar';

  @override
  String get agentActionsConfirmAppCloseTriggerTitle => 'Adicionar gatilho ao fechar o app?';

  @override
  String get agentActionsConfirmAppCloseTriggerMessage =>
      'Este gatilho roda quando o Plug Agente fecha e pode iniciar ou encerrar processos durante o shutdown.';

  @override
  String get agentActionsConfirmAppCloseTriggerConfirm => 'Usar fechamento do app';

  @override
  String get agentActionsConfirmAppCloseTriggerCancel => 'Cancelar';

  @override
  String get agentActionsConfirmElevatedTitle => 'Habilitar execucao elevada?';

  @override
  String get agentActionsConfirmElevatedMessage =>
      'As execucoes usam o helper elevado e privilegios de administrador nesta maquina. Instale e prepare o helper antes de habilitar.';

  @override
  String get agentActionsConfirmElevatedConfirm => 'Habilitar elevada';

  @override
  String get agentActionsConfirmElevatedCancel => 'Cancelar';

  @override
  String get agentActionsValidationTitle => 'Confira os campos da acao';

  @override
  String get agentActionsMaintenanceMode => 'Modo de manutencao';

  @override
  String get agentActionsMaintenanceModeInfoTitle => 'Modo de manutencao ativo';

  @override
  String get agentActionsMaintenanceModeInfoMessage =>
      'Execucoes agendadas, gatilhos de inicio/fechamento do app e execucoes remotas ficam pausadas. Voce ainda pode executar acoes nesta tela e editar definicoes.';

  @override
  String get agentActionsElevatedRunnerNotReadyTitle => 'Executor elevado nao preparado';

  @override
  String get agentActionsElevatedRunnerNotReadyMessage =>
      'Para usar execucao elevada, registre a tarefa do helper com privilegio alto. O Windows pode solicitar UAC uma vez.';

  @override
  String get agentActionsElevatedRunnerDegradedTitle => 'Executor elevado indisponivel';

  @override
  String get agentActionsElevatedRunnerDegradedMessage =>
      'O helper elevado falhou recentemente. Prepare novamente antes de executar acoes com privilegio alto.';

  @override
  String get agentActionsElevatedRunnerPrepare => 'Preparar executor elevado';

  @override
  String get agentActionsElevatedRunnerPreparing => 'Preparando executor elevado...';

  @override
  String get agentActionsFormRunElevated => 'Executar com privilegio elevado (helper Windows)';

  @override
  String get agentActionsFormRunElevatedHint => 'Requer o helper instalado e a tarefa agendada preparada neste agente.';

  @override
  String get agentActionsSubsystemStatusStartingTitle => 'Acoes do agente em inicializacao';

  @override
  String get agentActionsSubsystemStatusStartingMessage =>
      'O subsistema ainda esta inicializando. Executar e testar ficam desabilitados ate ficar pronto.';

  @override
  String get agentActionsSubsystemStatusDrainingTitle => 'Acoes do agente em encerramento';

  @override
  String get agentActionsSubsystemStatusDrainingMessage =>
      'Novas execucoes estao bloqueadas enquanto o Plug Agente fecha. Gatilhos de fechamento do app podem continuar.';

  @override
  String get agentActionsSubsystemStatusDegradedTitle => 'Alguns tipos de acao indisponiveis';

  @override
  String agentActionsSubsystemStatusDegradedMessage(String types) {
    return 'Tipos indisponiveis: $types. Outras acoes ainda podem ser executadas nesta tela.';
  }

  @override
  String get agentActionsSubsystemStatusDisabledTitle => 'Subsistema de acoes desativado';

  @override
  String get agentActionsSubsystemStatusDisabledMessage =>
      'O guard de runtime reporta o subsistema como desativado. Verifique as feature flags e reinicie o agente se necessario.';

  @override
  String get agentActionsSchedulerOperationalIssueTitle => 'Gatilhos agendados nao estao em execucao';

  @override
  String get agentActionsSchedulerInstanceLockedMessage =>
      'Outro processo do Plug Agente ja esta executando o agendador de acoes nesta pasta de dados. Feche a outra instancia ou use um diretorio de dados separado. Execucoes manuais e acoes remotas podem continuar funcionando nesta janela.';

  @override
  String get agentActionsSchedulerBootstrapFailedMessage =>
      'O agendador de acoes foi desativado apos falha na inicializacao. Reinicie o agente ou revise os gatilhos salvos. Execucoes manuais podem continuar ate corrigir a configuracao de agendamento.';

  @override
  String get agentActionsComObjectHandlersMissingTitle => 'Acoes COM nao estao prontas';

  @override
  String get agentActionsComObjectHandlersMissingMessage =>
      'Nenhum handler COM (ProgID/membro) esta registrado neste agente. Acoes COM falharao ate registrar handlers em ComObjectInvocationRegistry ou configurar o stub de homologacao (AGENT_ACTION_COM_STUB_ENABLED). Consulte agent.getHealth com_object_invocation_ready.';

  @override
  String get agentActionsDisabledTitle => 'Acoes desativadas';

  @override
  String get agentActionsDisabledMessage => 'As acoes do agente estao desativadas por feature flag.';

  @override
  String get agentActionsErrorTitle => 'Falha na operacao de acao';

  @override
  String get agentActionsSummaryActions => 'Acoes';

  @override
  String get agentActionsSummaryQueued => 'Na fila';

  @override
  String get agentActionsSummaryRunning => 'Executando';

  @override
  String get agentActionsSummaryFailed => 'Falhas';

  @override
  String get agentActionsSummaryMaintenance => 'Manutencao';

  @override
  String get agentActionsSummaryMaintenanceActive => 'Ativa';

  @override
  String get agentActionsSummaryComHandlers => 'Handlers COM';

  @override
  String get agentActionsSummaryComHandlersNone => 'Nenhum';

  @override
  String get agentActionsRetentionTitle => 'Retencao de dados';

  @override
  String get agentActionsRetentionDescription =>
      'A limpeza periodica remove linhas locais mais antigas que as janelas abaixo. Valores salvos aqui tem precedencia sobre variaveis de ambiente nesta instalacao.';

  @override
  String get agentActionsRetentionExecutionHistory => 'Historico de execucoes terminais';

  @override
  String agentActionsRetentionExecutionHistoryValue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionRemoteAudit => 'Auditoria remota agent.action';

  @override
  String agentActionsRetentionRemoteAuditValue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionCapturedOutput => 'Stdout/stderr capturados em linhas terminais';

  @override
  String agentActionsRetentionCapturedOutputValue(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String get agentActionsRetentionEnvVariables =>
      'Variaveis de ambiente (fallback): AGENT_ACTION_EXECUTION_RETENTION_DAYS, AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS, AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS';

  @override
  String get agentActionsRetentionSave => 'Salvar retencao';

  @override
  String get agentActionsRetentionReset => 'Descartar alteracoes';

  @override
  String get agentActionsRetentionUseEnvDefaults => 'Usar defaults de ambiente';

  @override
  String get agentActionsRetentionClearedTitle => 'Retencao restaurada';

  @override
  String get agentActionsRetentionClearedMessage =>
      'Os valores personalizados foram removidos. As janelas de limpeza passam a seguir variaveis de ambiente ou defaults do agente.';

  @override
  String get agentActionsRetentionSavedTitle => 'Retencao salva';

  @override
  String get agentActionsRetentionSavedMessage => 'As janelas de limpeza foram atualizadas nesta instalacao.';

  @override
  String get agentActionsRetentionInvalidValue => 'Informe numeros inteiros validos em todos os campos.';

  @override
  String get agentActionsRetentionPersistedHint =>
      'Valores personalizados estao salvos localmente e substituem o fallback de ambiente.';

  @override
  String get agentActionsEmptyActions => 'Nenhuma acao cadastrada.';

  @override
  String get agentActionsListFilterType => 'Tipo de acao';

  @override
  String get agentActionsListFilterSearch => 'Buscar acoes';

  @override
  String get agentActionsListFilterEmpty => 'Nenhuma acao corresponde aos filtros atuais.';

  @override
  String get agentActionsEmptySelection => 'Selecione uma acao para inspecionar detalhes de execucao.';

  @override
  String get agentActionsHistoryTitle => 'Historico de execucao';

  @override
  String get agentActionsHistoryFilterStatus => 'Status';

  @override
  String get agentActionsHistoryFilterSource => 'Origem';

  @override
  String get agentActionsHistoryFilterPeriod => 'Periodo';

  @override
  String get agentActionsHistoryFilterFailurePhase => 'Fase da falha';

  @override
  String get agentActionsHistoryFilterAll => 'Todos';

  @override
  String get agentActionsHistoryPeriodAll => 'Todos';

  @override
  String get agentActionsHistoryPeriodLast24Hours => 'Ultimas 24 horas';

  @override
  String get agentActionsHistoryPeriodLast3Days => 'Ultimos 3 dias';

  @override
  String get agentActionsRemoteAuditTitle => 'Auditoria remota agent.action';

  @override
  String get agentActionsRemoteAuditDescription =>
      'Linhas recentes de JSON-RPC do Hub e de ciclo de vida de execucao para agent.action.* (append-only; retencao e purge continuam valendo).';

  @override
  String get agentActionsRemoteAuditFilterAll => 'Todas';

  @override
  String get agentActionsRemoteAuditFilterRpc => 'RPC';

  @override
  String get agentActionsRemoteAuditFilterLifecycle => 'Ciclo de vida';

  @override
  String get agentActionsRemoteAuditFilterEmpty => 'Nenhuma linha corresponde a este filtro.';

  @override
  String get agentActionsRemoteAuditOutcomeReceived => 'Recebido';

  @override
  String get agentActionsRemoteAuditOutcomeSuccess => 'Sucesso';

  @override
  String get agentActionsRemoteAuditOutcomeRpcError => 'Erro RPC';

  @override
  String get agentActionsRemoteAuditOutcomeAuthorizationDenied => 'Autorizacao negada';

  @override
  String get agentActionsRemoteAuditOutcomeNotificationRejected => 'Notificacao rejeitada';

  @override
  String get agentActionsRemoteAuditOutcomeRateLimited => 'Rate limit';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleEnqueued => 'Enfileirado';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleStarted => 'Iniciado';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleCancelRequested => 'Cancelamento solicitado';

  @override
  String get agentActionsRemoteAuditOutcomeLifecycleFinished => 'Finalizado';

  @override
  String get agentActionsRemoteAuditEmpty => 'Nenhuma linha de auditoria remota ainda.';

  @override
  String get agentActionsRemoteAuditRefresh => 'Recarregar';

  @override
  String get agentActionsRemoteAuditCopyJson => 'Copiar como JSON';

  @override
  String get agentActionsRemoteAuditCopiedToast => 'Auditoria copiada para a area de transferencia.';

  @override
  String get agentActionsRemoteAuditShowInHistory => 'Ver no historico';

  @override
  String agentActionsRemoteAuditExecutionNotInHistory(Object executionId) {
    return 'A execucao $executionId nao esta no historico carregado. Pode estar fora da retencao ou do limite da lista.';
  }

  @override
  String agentActionsRemoteAuditRuntimeInstanceMismatch(Object executionId, Object auditInstanceId) {
    return 'A execucao $executionId pertence a outra instalacao do agente (instancia da auditoria $auditInstanceId). O historico local so destaca quando a instancia de runtime coincide.';
  }

  @override
  String get agentActionsRemoteAuditFieldAction => 'Acao';

  @override
  String get agentActionsRemoteAuditFieldExecution => 'Execucao';

  @override
  String get agentActionsRemoteAuditFieldTrace => 'Trace';

  @override
  String get agentActionsRemoteAuditFieldRequestedBy => 'Solicitante';

  @override
  String get agentActionsRemoteAuditFieldIdempotencyKey => 'Idempotencia';

  @override
  String get agentActionsRemoteAuditFieldReason => 'Motivo';

  @override
  String get agentActionsRemoteAuditFieldClient => 'Cliente';

  @override
  String get agentActionsRemoteAuditFieldRuntimeInstance => 'Instancia';

  @override
  String get agentActionsRemoteAuditFieldRuntimeSession => 'Sessao';

  @override
  String get agentActionsRemoteAuditReasonMissingClientToken => 'Token de cliente ausente';

  @override
  String get agentActionsRemoteAuditReasonPermissionDenied => 'Permissao negada';

  @override
  String get agentActionsRemoteAuditReasonRemoteRateLimited => 'Rate limit remoto';

  @override
  String get agentActionsRemoteAuditReasonRemoteDisabled => 'Acoes remotas desativadas';

  @override
  String get agentActionsRemoteAuditReasonFeatureDisabled => 'Acoes do agente desativadas';

  @override
  String get agentActionsRemoteAuditReasonMaintenanceMode => 'Modo de manutencao';

  @override
  String get agentActionsRemoteAuditReasonNotificationNotAllowed => 'Notificacao nao permitida';

  @override
  String get agentActionsRemoteAuditReasonRemoteContextNotSupported => 'Contexto remoto nao suportado';

  @override
  String get agentActionsRemoteAuditReasonIdempotencyRequired => 'Chave de idempotencia obrigatoria';

  @override
  String get agentActionsRemoteAuditReasonIdempotencyMismatch => 'Fingerprint de idempotencia divergente';

  @override
  String get agentActionsRemoteAuditReasonBatchNotAllowed => 'Metodo nao permitido em batch';

  @override
  String get agentActionsRemoteAuditReasonExecutionNotFound => 'Execucao nao encontrada';

  @override
  String get agentActionsRemoteAuditReasonAlreadyFinished => 'Ja finalizada';

  @override
  String get agentActionsRemoteAuditReasonKillFailed => 'Falha ao encerrar processo';

  @override
  String get agentActionsEmptyHistory => 'Nenhuma execucao registrada para esta acao.';

  @override
  String get agentActionsTriggersTitle => 'Agendas e gatilhos';

  @override
  String get agentActionsTriggersEmpty => 'Nenhum gatilho salvo para esta acao.';

  @override
  String get agentActionsTriggersLoading => 'Carregando gatilhos…';

  @override
  String get agentActionsTriggerEnabled => 'Ativo';

  @override
  String get agentActionsTriggerDisabled => 'Desativado';

  @override
  String get agentActionsTriggerUnnamed => 'Gatilho sem nome';

  @override
  String get agentActionsTriggerNotScheduled => 'Sem agendamento';

  @override
  String agentActionsTriggerNextRun(Object when) {
    return 'Proxima execucao: $when';
  }

  @override
  String agentActionsTriggerSummaryTimeZone(Object ianaId) {
    return 'Fuso IANA: $ianaId';
  }

  @override
  String get agentActionsTriggerSummaryCatchUpEnabled => 'Execucao de atrasadas ativa';

  @override
  String get agentActionsTriggerTypeManual => 'Manual';

  @override
  String get agentActionsTriggerTypeRemote => 'Remoto';

  @override
  String get agentActionsTriggerTypeOnce => 'Unica vez';

  @override
  String get agentActionsTriggerTypeInterval => 'Intervalo';

  @override
  String get agentActionsTriggerTypeDaily => 'Diario';

  @override
  String get agentActionsTriggerTypeWeekly => 'Semanal';

  @override
  String get agentActionsTriggerTypeMonthly => 'Mensal';

  @override
  String get agentActionsTriggerTypeAppStart => 'Inicio do app';

  @override
  String get agentActionsTriggerTypeAppClose => 'Encerramento do app';

  @override
  String get agentActionsTriggerDelete => 'Excluir gatilho';

  @override
  String get agentActionsTriggerDeleteConfirmTitle => 'Excluir gatilho';

  @override
  String agentActionsTriggerDeleteConfirmMessage(Object triggerLabel) {
    return 'Excluir \"$triggerLabel\"? As execucoes agendadas deste gatilho param.';
  }

  @override
  String get agentActionsTriggerDeleteConfirm => 'Excluir';

  @override
  String get agentActionsTriggerDeleteCancel => 'Cancelar';

  @override
  String get agentActionsTriggerAdd => 'Adicionar gatilho';

  @override
  String get agentActionsTriggerEdit => 'Editar gatilho';

  @override
  String get agentActionsTriggerSave => 'Salvar gatilho';

  @override
  String get agentActionsTriggerCancel => 'Cancelar';

  @override
  String get agentActionsTriggerEditorTitleNew => 'Novo gatilho';

  @override
  String get agentActionsTriggerEditorTitleEdit => 'Editar gatilho';

  @override
  String get agentActionsTriggerFieldName => 'Nome de exibicao';

  @override
  String get agentActionsTriggerFieldType => 'Tipo de gatilho';

  @override
  String get agentActionsTriggerFieldTimezone => 'Fuso horario IANA (opcional)';

  @override
  String get agentActionsTriggerFieldTimezoneFilter => 'Filtrar fusos IANA';

  @override
  String get agentActionsTriggerHintTimezoneFilter => 'ex.: America, Europe, UTC';

  @override
  String get agentActionsTriggerHintTimezonePick =>
      'Toque em uma linha para preencher o campo acima. Deixe vazio para usar o fuso padrao do dispositivo.';

  @override
  String get agentActionsTriggerHintTimezoneSearchEmpty => 'Digite no filtro para buscar fusos IANA.';

  @override
  String get agentActionsTriggerTimezoneNoMatches => 'Nenhum fuso corresponde ao filtro.';

  @override
  String agentActionsTriggerTimezoneMatchesTruncated(int count) {
    return 'Mostrando os primeiros $count resultados. Afine o filtro.';
  }

  @override
  String get agentActionsTriggerFieldStartAt => 'Data e hora de inicio';

  @override
  String get agentActionsTriggerFieldStartAtOptional => 'Ativo a partir de (opcional)';

  @override
  String get agentActionsTriggerFieldEndAtOptional => 'Ativo ate (opcional)';

  @override
  String get agentActionsTriggerFieldIntervalMinutes => 'Intervalo (minutos)';

  @override
  String get agentActionsTriggerFieldTimeOfDay => 'Horario do dia';

  @override
  String get agentActionsTriggerHintTimeOfDay => 'HH:mm (24 horas)';

  @override
  String get agentActionsTriggerFieldWeekdays => 'Dias da semana';

  @override
  String get agentActionsTriggerFieldDayOfMonth => 'Dia do mes (1-31)';

  @override
  String get agentActionsTriggerHintDateTime => 'Formato: yyyy-MM-dd HH:mm (local)';

  @override
  String get agentActionsTriggerFieldIgnoreMissedRuns => 'Ignorar execucoes perdidas durante inatividade';

  @override
  String get agentActionsTriggerHintIgnoreMissedRuns =>
      'Desmarque para tentar executar agendamentos perdidos com o app fechado, quando o tipo de gatilho suportar recuperacao.';

  @override
  String get agentActionsTriggerValidationTitle => 'Revise os campos do gatilho';

  @override
  String get agentActionsTriggerValidationInvalidStartAt => 'Informe uma data e hora de inicio validas.';

  @override
  String get agentActionsTriggerValidationInvalidIntervalMinutes => 'Informe um numero inteiro positivo de minutos.';

  @override
  String get agentActionsTriggerValidationInvalidTimeOfDay => 'Informe o horario como HH:mm em relogio de 24 horas.';

  @override
  String get agentActionsTriggerValidationWeekdaysRequired => 'Selecione pelo menos um dia da semana.';

  @override
  String get agentActionsTriggerValidationInvalidDayOfMonth => 'Informe um dia do mes entre 1 e 31.';

  @override
  String get agentActionsTriggerWeekdayMon => 'Seg';

  @override
  String get agentActionsTriggerWeekdayTue => 'Ter';

  @override
  String get agentActionsTriggerWeekdayWed => 'Qua';

  @override
  String get agentActionsTriggerWeekdayThu => 'Qui';

  @override
  String get agentActionsTriggerWeekdayFri => 'Sex';

  @override
  String get agentActionsTriggerWeekdaySat => 'Sab';

  @override
  String get agentActionsTriggerWeekdaySun => 'Dom';

  @override
  String get agentActionsRequestedAt => 'Solicitada em';

  @override
  String get agentActionsExitCode => 'Codigo de saida';

  @override
  String get agentActionsSourceLocalUi => 'UI local';

  @override
  String get agentActionsSourceScheduler => 'Agendador';

  @override
  String get agentActionsSourceRemoteHub => 'Hub';

  @override
  String get agentActionsSourceAppLifecycle => 'Ciclo de vida do app';

  @override
  String get agentActionsDiagnosticsCopySupport => 'Copiar JSON de suporte';

  @override
  String get agentActionsDiagnosticsCopiedToast => 'Diagnostico copiado para a area de transferencia.';

  @override
  String get agentActionsDiagnosticsTitle => 'Diagnostico';

  @override
  String get agentActionsDiagnosticsExecutionId => 'Execucao';

  @override
  String get agentActionsDiagnosticsSource => 'Origem';

  @override
  String get agentActionsDiagnosticsPid => 'PID';

  @override
  String get agentActionsDiagnosticsStartedAt => 'Iniciada';

  @override
  String get agentActionsDiagnosticsFinishedAt => 'Finalizada';

  @override
  String get agentActionsDiagnosticsTimeoutAt => 'Timeout';

  @override
  String get agentActionsDiagnosticsDuration => 'Duracao';

  @override
  String get agentActionsDiagnosticsExecutable => 'Executavel';

  @override
  String get agentActionsDiagnosticsArgumentCount => 'Argumentos';

  @override
  String get agentActionsDiagnosticsCommandPreview => 'Preview do comando';

  @override
  String get agentActionsDiagnosticsFailureCode => 'Codigo de falha';

  @override
  String get agentActionsDiagnosticsFailurePhase => 'Fase da falha';

  @override
  String get agentActionsFailurePhaseExecutionPreflight => 'Preflight de execucao';

  @override
  String get agentActionsFailurePhaseDefinitionValidation => 'Validacao da definicao';

  @override
  String get agentActionsFailurePhaseStartProcess => 'Inicio do processo';

  @override
  String get agentActionsFailurePhaseStdinSetup => 'Configuracao de stdin';

  @override
  String get agentActionsFailurePhaseProcessRuntime => 'Execucao do processo';

  @override
  String get agentActionsFailurePhaseProcessExit => 'Saida do processo';

  @override
  String get agentActionsFailurePhaseQueue => 'Fila';

  @override
  String get agentActionsFailurePhaseTimeout => 'Timeout';

  @override
  String get agentActionsFailurePhaseAuthorization => 'Autorizacao';

  @override
  String get agentActionsFailurePhaseValidation => 'Validacao';

  @override
  String get agentActionsFailurePhaseLookup => 'Consulta';

  @override
  String get agentActionsFailurePhaseCancel => 'Cancelamento';

  @override
  String get agentActionsFailurePhasePlatformCheck => 'Verificacao de plataforma';

  @override
  String get agentActionsFailurePhaseSmtpSend => 'Envio SMTP';

  @override
  String get agentActionsFailurePhaseExecutionSend => 'Preparacao do envio';

  @override
  String get agentActionsFailurePhaseElevatedSubmit => 'Submissao elevada';

  @override
  String get agentActionsFailurePhaseBootstrapReconciliation => 'Reconciliacao na inicializacao';

  @override
  String agentActionsExecutionFailurePhaseLabel(String phase) {
    return 'Falhou na fase: $phase';
  }

  @override
  String get agentActionsDiagnosticsCorrectiveAction => 'Acao corretiva';

  @override
  String get agentActionsDiagnosticsCorrectivePath =>
      'Revise o caminho salvo, valide o arquivo ou diretorio novamente e atualize a acao antes de executar.';

  @override
  String get agentActionsDiagnosticsCorrectiveRunner =>
      'Confira o caminho do executavel, interpretador ou runner configurado e valide a acao novamente.';

  @override
  String get agentActionsDiagnosticsCorrectiveExitCode =>
      'Revise o exit code e a saida redigida. Ajuste os codigos aceitos ou corrija o comando executado.';

  @override
  String get agentActionsDiagnosticsCorrectiveQueue =>
      'Aguarde a fila reduzir ou ajuste os limites de concorrencia e enfileiramento da acao.';

  @override
  String get agentActionsDiagnosticsCorrectiveTimeout =>
      'Revise o timeout configurado e investigue por que o processo nao concluiu dentro da janela esperada.';

  @override
  String get agentActionsDiagnosticsCorrectiveKill =>
      'Verifique se o processo principal ainda esta em execucao e tente cancelar novamente apos revisar PID e permissao.';

  @override
  String get agentActionsDiagnosticsCorrectiveDefinitionValidation =>
      'Revise os campos obrigatorios e valide o cadastro da acao novamente antes de executar.';

  @override
  String get agentActionsDiagnosticsCorrectivePreflight =>
      'Revalide paths, permissoes, contexto e pre-requisitos locais antes de iniciar a execucao.';

  @override
  String get agentActionsDiagnosticsCorrectiveStartProcess =>
      'Confira executavel, argumentos e diretorio de trabalho antes de tentar iniciar o processo novamente.';

  @override
  String get agentActionsDiagnosticsCorrectiveRuntime =>
      'Consulte a saida redigida e os detalhes operacionais para identificar a falha ocorrida durante a execucao.';

  @override
  String get agentActionsDiagnosticsStdout => 'stdout';

  @override
  String get agentActionsDiagnosticsStderr => 'stderr';

  @override
  String get agentActionsDiagnosticsTruncated => 'truncado';

  @override
  String get agentActionsDiagnosticsStoredInChunks => 'armazenado em segmentos';

  @override
  String get agentActionsExecutionOutputInChunks => 'saida grande em segmentos';

  @override
  String get agentActionsDiagnosticsOutputLoadFailed => 'Nao foi possivel carregar a saida capturada';

  @override
  String get agentActionsDiagnosticsLoadMoreStdout => 'Carregar mais (stdout)';

  @override
  String get agentActionsDiagnosticsLoadMoreStderr => 'Carregar mais (stderr)';

  @override
  String get agentActionsDiagnosticsDefinitionSnapshotHash => 'Hash do snapshot da definicao';

  @override
  String get agentActionsDiagnosticsContextHash => 'Hash do contexto';

  @override
  String get agentActionsDiagnosticsRedactionApplied => 'Redacao aplicada';

  @override
  String get agentActionsDiagnosticsValueYes => 'Sim';

  @override
  String get agentActionsDiagnosticsValueNo => 'Nao';

  @override
  String get agentActionsDiagnosticsQueueStartedAt => 'Fila iniciada';

  @override
  String get agentActionsDiagnosticsIdempotencyKey => 'Chave de idempotencia';

  @override
  String get agentActionsDiagnosticsRequestedBy => 'Solicitado por';

  @override
  String get agentActionsDiagnosticsTraceId => 'Trace id';

  @override
  String get agentActionsDiagnosticsRuntimeInstanceId => 'ID da instancia (runtime)';

  @override
  String get agentActionsDiagnosticsRuntimeSessionId => 'ID da sessao (runtime)';

  @override
  String get agentActionsDiagnosticsTriggerId => 'Gatilho';

  @override
  String get agentActionsDiagnosticsTriggerType => 'Tipo de gatilho';

  @override
  String get agentActionsDiagnosticsScheduledAt => 'Agendada para';

  @override
  String get agentActionsDiagnosticsTriggeredAt => 'Disparada em';

  @override
  String get agentActionsTypeCommandLine => 'Linha de comando';

  @override
  String get agentActionsTypeExecutable => 'Executavel';

  @override
  String get agentActionsTypeScript => 'Script';

  @override
  String get agentActionsTypeJar => 'JAR';

  @override
  String get agentActionsTypeEmail => 'E-mail';

  @override
  String get agentActionsTypeComObject => 'Objeto COM';

  @override
  String get agentActionsTypeDeveloper => 'Developer';

  @override
  String get agentActionsStateActive => 'Ativa';

  @override
  String get agentActionsStatePaused => 'Pausada';

  @override
  String get agentActionsStateDisabled => 'Desativada';

  @override
  String get agentActionsStateNeedsValidation => 'Precisa validar';

  @override
  String get agentActionsStatusQueued => 'Na fila';

  @override
  String get agentActionsStatusRunning => 'Executando';

  @override
  String get agentActionsStatusSucceeded => 'Sucesso';

  @override
  String get agentActionsStatusFailed => 'Falha';

  @override
  String get agentActionsStatusSkipped => 'Ignorada';

  @override
  String get agentActionsStatusCancelled => 'Cancelada';

  @override
  String get agentActionsStatusKilled => 'Finalizada';

  @override
  String get agentActionsStatusTimedOut => 'Timeout';

  @override
  String get agentActionsStatusInterrupted => 'Interrompida';

  @override
  String get agentActionsStatusUnknown => 'Desconhecida';

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
  String get btnClose => 'Fechar';

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
  String get wsLogTabStream => 'Fluxo';

  @override
  String get wsLogTabSqlInvestigation => 'SQL';

  @override
  String get wsSqlInvestigationClear => 'Limpar SQL';

  @override
  String get wsSqlInvestigationEmpty => 'Nenhum evento de SQL para exibir ainda';

  @override
  String get wsSqlInvestigationKindAuth => 'Rejeição de autorização';

  @override
  String get wsSqlInvestigationKindExec => 'Erro de execução';

  @override
  String get wsSqlInvestigationRpcId => 'ID da requisição';

  @override
  String get wsSqlInvestigationInternalId => 'ID interno de execução';

  @override
  String get wsSqlInvestigationReason => 'Motivo';

  @override
  String get wsSqlInvestigationOriginalSql => 'SQL recebida';

  @override
  String get wsSqlInvestigationEffectiveSql => 'SQL enviada ao banco';

  @override
  String get wsSqlInvestigationNotExecuted => 'Não executada no banco';

  @override
  String get wsSqlInvestigationError => 'Erro';

  @override
  String get wsSqlInvestigationExecutedInDb => 'Enviada ao servidor ODBC';

  @override
  String get wsSqlInvestigationExecution => 'Execução';

  @override
  String get wsSqlInvestigationMetaClientId => 'ID do cliente';

  @override
  String get wsSqlInvestigationMetaResource => 'Recurso';

  @override
  String get wsSqlInvestigationMetaOperation => 'Operação';

  @override
  String get wsSqlInvestigationShowMore => 'Ver mais';

  @override
  String get wsSqlInvestigationShowLess => 'Ver menos';

  @override
  String get wsSqlInvestigationCopy => 'Copiar';

  @override
  String get wsSqlInvestigationCopyTooltip => 'Copiar SQL para a área de transferência';

  @override
  String get wsSqlInvestigationClearTooltip => 'Limpar a lista de eventos de investigação SQL';

  @override
  String get wsLogClearTooltip => 'Limpar o registo de mensagens WebSocket';

  @override
  String get wsLogToggleEnabledTooltip => 'Ativar ou pausar a captura de mensagens WebSocket';

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
  String get configTabPreferences => 'Preferências';

  @override
  String get configTabUpdatesAbout => 'Atualizações e sobre';

  @override
  String get configTabBackup => 'Cópia de segurança';

  @override
  String get configTabWebSocket => 'WebSocket';

  @override
  String get configBackupSectionTitle => 'Cópia de segurança local';

  @override
  String get configBackupIntro =>
      'Exporte ou restaure a base local do agente (configuração) e o ficheiro de definições globais. O arquivo pode conter credenciais do hub guardadas na base. Segredos que existem só no armazenamento seguro do Windows não são incluídos—pode ser necessário voltar a autenticar após restaurar.';

  @override
  String get configBackupDuplicateNote =>
      'Restaurar a mesma cópia de segurança em duas máquinas pode registar o mesmo agente duas vezes. A aplicação verifica o hub quando possível; se a verificação falhar, deve confirmar que aceita o risco.';

  @override
  String get configBackupSingleInstanceNote =>
      'Não execute duas cópias da aplicação sobre a mesma pasta de dados global.';

  @override
  String configBackupRestoreDiagnosticsHint(String fileName) {
    return 'Se a restauração falhar depois de a aplicação fechar, os detalhes ficam em $fileName na pasta de dados da aplicação.';
  }

  @override
  String get configBackupButtonExport => 'Exportar cópia de segurança…';

  @override
  String get configBackupButtonRestore => 'Restaurar a partir da cópia…';

  @override
  String get configBackupExporting => 'A exportar cópia de segurança…';

  @override
  String get configBackupRestoring => 'A preparar restauração…';

  @override
  String get configBackupExportSuccessTitle => 'Cópia guardada';

  @override
  String get configBackupExportSuccessMessage => 'O ficheiro de cópia de segurança foi criado com sucesso.';

  @override
  String get configBackupRestoreDialogTitle => 'Restaurar cópia de segurança';

  @override
  String get configBackupRestoreDialogBody =>
      'Isto substitui a base local e as definições. A aplicação será fechada—volte a abri-la depois. Os ficheiros atuais são copiados para .bak antes da substituição.';

  @override
  String get configBackupRestoreDuplicateWarning =>
      'Este ID de agente parece ligado no hub. Restaurar pode duplicar uma sessão ativa a menos que a outra máquina esteja offline.';

  @override
  String get configBackupRestoreVerifyWarning =>
      'Não foi possível verificar se este agente já está ligado (rede ou sessão expirada). Confirme que nenhuma outra máquina está a usar esta mesma cópia.';

  @override
  String get configBackupRestoreInstallationMismatch =>
      'Esta cópia foi criada noutra instalação (ID de instalação diferente).';

  @override
  String get configBackupCheckboxAcknowledgeDuplicate =>
      'Confirmo que a outra sessão está offline ou aceito o risco de agente duplicado.';

  @override
  String get configBackupCheckboxAcknowledgeUncertain =>
      'Compreendo que o hub não pôde ser verificado e aceito o risco.';

  @override
  String get configBackupRestoreConfirm => 'Restaurar e sair';

  @override
  String get configBackupCancel => 'Cancelar';

  @override
  String get configBackupErrMissingManifestOrDb => 'O arquivo não contém o manifest ou a base de dados.';

  @override
  String get configBackupErrInvalidManifest => 'O manifest da cópia é inválido.';

  @override
  String get configBackupErrUnsupportedFormat => 'Este formato de cópia não é suportado.';

  @override
  String get configBackupErrDbVersion => 'Não foi possível ler a versão do esquema na base da cópia.';

  @override
  String get configBackupErrNewerBackup =>
      'Esta cópia foi criada com uma versão mais recente da aplicação. Atualize antes de restaurar.';

  @override
  String get configBackupErrInvalidEntry => 'O arquivo contém uma entrada de ficheiro inválida.';

  @override
  String get configBackupErrExportDbNotFound => 'Ficheiro da base local não encontrado.';

  @override
  String get configBackupErrExportZip => 'Falha ao criar o arquivo de cópia.';

  @override
  String get configBackupErrExportWrite => 'Não foi possível gravar o ficheiro de cópia.';

  @override
  String get configBackupErrExportGeneric => 'Erro inesperado ao exportar a cópia.';

  @override
  String get configBackupErrReadZip => 'Não foi possível ler o ficheiro de cópia.';

  @override
  String get configBackupErrStageGeneric => 'Falha ao ler o arquivo de cópia.';

  @override
  String get configBackupErrApplyMissingDb => 'Ficheiro da base preparada em falta.';

  @override
  String get configBackupErrApplyWrite => 'Não foi possível aplicar os ficheiros da cópia.';

  @override
  String get configBackupRestoreFailedTitle => 'Falha na restauração';

  @override
  String get configBackupExportFailedTitle => 'Falha na exportação';

  @override
  String get configBackupRestoreRestartNotice =>
      'A aplicação será fechada. Abra-a novamente para usar os dados restaurados.';

  @override
  String get configBackupRestoreOlderSchemaNote =>
      'Esta cópia usa um esquema de base de dados mais antigo. A aplicação irá migrá-lo no próximo arranque.';

  @override
  String get configLastUpdateNever => 'Nunca verificado';

  @override
  String get configUpdatesChecking => 'Verificando atualizações...';

  @override
  String get configLastUpdatePrefix => 'Última verificação: ';

  @override
  String get configLastBackgroundUpdatePrefix => 'Última verificação em segundo plano: ';

  @override
  String get configLastAutomaticUpdatePrefix => 'Última verificação automática: ';

  @override
  String get configUpdatesAvailable => 'Uma nova versão está disponível. Siga as instruções para atualizar.';

  @override
  String get configUpdatesNotAvailable => 'Você já está na versão mais recente.';

  @override
  String get configUpdatesNotAvailableHint =>
      'Se você acabou de publicar uma nova versão, aguarde até 5 minutos e tente novamente.';

  @override
  String get configAutomaticSilentUpdatesToggle => 'Instalar atualizações automaticamente';

  @override
  String get configAutomaticSilentUpdatesDescription =>
      'Baixa, valida e inicia o instalador em modo silencioso. O Windows ainda pode solicitar UAC.';

  @override
  String get configAutomaticSilentUpdatesEnabled => 'Instalação automática de atualizações ativada.';

  @override
  String get configAutomaticSilentUpdatesDisabled => 'Instalação automática de atualizações desativada.';

  @override
  String get configAutomaticSilentUpdatesCheckNow => 'Tentar atualização automática agora';

  @override
  String get configAutoUpdateFeedOfficial => 'Feed: oficial';

  @override
  String get configAutoUpdateFeedCustom => 'Feed: personalizado';

  @override
  String get configAutoUpdateNotConfigured =>
      'Auto-update está indisponível porque o feed configurado é inválido. Remova AUTO_UPDATE_FEED_URL para usar o feed oficial ou informe um feed Sparkle (.xml).';

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
  String get configUpdateTechnicalBackgroundTitle => 'Detalhes técnicos em segundo plano';

  @override
  String get configUpdateTechnicalAutomaticTitle => 'Detalhes técnicos da atualização automática';

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
  String get configUpdateTechnicalProbeRequestUrl => 'URL do probe';

  @override
  String get configUpdateTechnicalProbeSucceeded => 'Probe HTTP bem-sucedido';

  @override
  String get configUpdateTechnicalCompletionSource => 'Resultado do check';

  @override
  String get configUpdateTechnicalTriggerDurationMs => 'Tempo do disparo (ms)';

  @override
  String get configUpdateTechnicalTotalDurationMs => 'Tempo total (ms)';

  @override
  String get configUpdateTechnicalFeedItemCount => 'Itens no feed';

  @override
  String get configUpdateTechnicalRemoteVersion => 'Versão remota';

  @override
  String get configUpdateTechnicalAssetName => 'Nome do asset';

  @override
  String get configUpdateTechnicalAssetUrl => 'URL do asset';

  @override
  String get configUpdateTechnicalAssetSize => 'Tamanho do asset';

  @override
  String get configUpdateTechnicalSha256 => 'SHA-256 esperado';

  @override
  String get configUpdateTechnicalActualSha256 => 'SHA-256 real';

  @override
  String get configUpdateTechnicalHashValidationStatus => 'Validação do hash';

  @override
  String get configUpdateTechnicalRolloutChannel => 'Canal de update';

  @override
  String get configUpdateTechnicalRolloutPercentage => 'Percentual de rollout';

  @override
  String get configUpdateTechnicalRolloutBucket => 'Bucket de rollout';

  @override
  String get configUpdateTechnicalRolloutEligible => 'Elegível no rollout';

  @override
  String get configUpdateTechnicalPendingVersion => 'Versão pendente';

  @override
  String get configUpdateTechnicalInstallerPath => 'Caminho do instalador';

  @override
  String get configUpdateTechnicalInstallerLogPath => 'Log do instalador';

  @override
  String get configUpdateTechnicalInstallDirectory => 'Diretório de instalação';

  @override
  String get configUpdateTechnicalUpdateDirectorySecurity => 'Segurança do diretório de updates';

  @override
  String get configUpdateTechnicalInstallDirectoryWritable => 'Diretório de instalação gravável';

  @override
  String get configUpdateTechnicalSilentStrategy => 'Estratégia silenciosa';

  @override
  String get configUpdateTechnicalLauncherPath => 'Caminho do launcher';

  @override
  String get configUpdateTechnicalLauncherStatusPath => 'Status do launcher';

  @override
  String get configUpdateTechnicalLauncherState => 'Estado do launcher';

  @override
  String get configUpdateTechnicalAppPid => 'PID do app';

  @override
  String get configUpdateTechnicalSignatureStatus => 'Status da assinatura';

  @override
  String get configUpdateTechnicalSignatureRequired => 'Assinatura obrigatória';

  @override
  String get configUpdateTechnicalWaitForAppExitDurationMs => 'Espera pelo fechamento do app (ms)';

  @override
  String get configUpdateTechnicalNonAdminExitCode => 'Exit code sem admin';

  @override
  String get configUpdateTechnicalNonAdminDurationMs => 'Duração sem admin (ms)';

  @override
  String get configUpdateTechnicalElevatedExitCode => 'Exit code elevado';

  @override
  String get configUpdateTechnicalElevatedDurationMs => 'Duração elevada (ms)';

  @override
  String get configUpdateTechnicalElevatedRetryStarted => 'Retry elevado iniciado';

  @override
  String get configUpdateTechnicalElevatedCancelled => 'Prompt elevado cancelado';

  @override
  String get configUpdateTechnicalAutomaticFailureCount => 'Contagem de falhas automáticas';

  @override
  String get configUpdateTechnicalAutomaticCooldownUntil => 'Cooldown automático até';

  @override
  String get configUpdateTechnicalUpdaterError => 'Erro do updater';

  @override
  String get configUpdateTechnicalAppcastError => 'Erro ao ler appcast';

  @override
  String get configUpdateCompletionSourceUpdateAvailable => 'Atualização disponível';

  @override
  String get configUpdateCompletionSourceUpdateNotAvailable => 'Sem atualização disponível';

  @override
  String get configUpdateCompletionSourceUpdaterError => 'Falha retornada pelo updater';

  @override
  String get configUpdateCompletionSourceTriggerTimeout => 'Timeout ao disparar o updater';

  @override
  String get configUpdateCompletionSourceCompletionTimeout => 'Timeout aguardando retorno do updater';

  @override
  String get configUpdateCompletionSourceTriggerFailure => 'Falha ao iniciar a checagem';

  @override
  String get configUpdateCompletionSourceNotInitialized => 'Auto-update não inicializado';

  @override
  String get configUpdateCompletionSourceCircuitOpen => 'Checagens pausadas por timeouts repetidos';

  @override
  String get configUpdateCompletionSourceAutomaticDisabled => 'Instalação automática desativada';

  @override
  String get configUpdateCompletionSourceAutomaticPendingCompleted => 'Atualização automática pendente concluída';

  @override
  String get configUpdateCompletionSourceAutomaticPendingFailed => 'Atualização automática pendente não concluída';

  @override
  String get configUpdateCompletionSourceAutomaticUpdateNotAvailable => 'Sem atualização automática disponível';

  @override
  String get configUpdateCompletionSourceAutomaticValidationFailure => 'Validação da atualização automática falhou';

  @override
  String get configUpdateCompletionSourceAutomaticDownloadFailure => 'Download da atualização automática falhou';

  @override
  String get configUpdateCompletionSourceAutomaticInstallStarted => 'Instalador automático iniciado';

  @override
  String get configUpdateCompletionSourceAutomaticInstallFailure => 'Falha ao iniciar instalador automático';

  @override
  String get configUpdateCompletionSourceAutomaticCooldown => 'Atualizações automáticas pausadas';

  @override
  String get configUpdateCompletionSourceAutomaticRolloutSkipped => 'Atualização automática ignorada pelo rollout';

  @override
  String get configCopyUpdateDiagnostics => 'Copiar diagnóstico de update';

  @override
  String get configUpdateDiagnosticsCopied => 'Diagnóstico de update copiado.';

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
  String get gsToggleStartMinimizedNextLaunchHint => 'Aplicado na próxima inicialização do Windows.';

  @override
  String get gsToggleStartMinimizedRequiresTray => 'Requer suporte à bandeja neste ambiente.';

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
  String get gsButtonRepairStartup => 'Reparar';

  @override
  String get gsStartupLaunchConfigurationReady => 'Entrada de inicialização pronta.';

  @override
  String get gsStartupLaunchConfigurationRepaired => 'Entrada de inicialização reparada.';

  @override
  String get gsStartupLaunchConfigurationRepairFailed => 'Entrada de inicialização precisa de reparo';

  @override
  String get gsErrorStartupToggleFailed => 'Falha ao alterar configuração de inicialização';

  @override
  String get gsErrorStartupServiceUnavailable => 'Configurações de inicialização não disponíveis neste ambiente';

  @override
  String get gsErrorStartupOpenSystemSettingsFailed => 'Falha ao abrir configurações do sistema';

  @override
  String get gsErrorSettingsPersistenceFailed => 'Falha ao salvar preferência local';

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
  String get diagnosticsHubHardReloginEnabledLabel => 'Ativar fallback de hard relogin automático';

  @override
  String get diagnosticsHubHardReloginEnabledDescription =>
      'Quando ativado, após falhas repetidas de reconexão o agente tentará logout, login com credenciais salvas e reconexão do socket.';

  @override
  String get diagnosticsHubHardReloginThresholdLabel => 'Falhas de reconexão antes do hard relogin';

  @override
  String get diagnosticsHubHardReloginThresholdHint => 'Intervalo permitido: 1-20. Valores menores escalam mais cedo.';

  @override
  String get diagnosticsHubHardReloginInvalidThreshold => 'Digite um número inteiro entre 1 e 20.';

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
  String get msgRpcAgentActionsTemporarilyUnavailable =>
      'As ações do agente estão indisponíveis no momento. Aguarde e tente novamente.';

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
  String get ctFieldName => 'Nome (opcional)';

  @override
  String get ctHintName => 'Ex: Cliente XYZ — Produção';

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
  String get ctInfoClientTokenLoadFailed => 'Nao foi possivel carregar o segredo deste token';

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
  String get ctNoRulesConfigured => 'Nenhuma regra específica configurada';

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
  String get ctErrorRuleOrGlobalPermissionsRequired =>
      'Adicione ao menos uma regra valida quando o escopo global estiver desligado.';

  @override
  String get ctErrorGlobalPermissionRequired =>
      'Selecione ao menos uma permissao global quando all_tables ou all_views estiver ativo.';

  @override
  String get ctErrorPayloadMustBeJsonObject => 'Payload deve ser um objeto JSON valido.';

  @override
  String get ctErrorPayloadInvalidJson => 'Payload JSON invalido.';

  @override
  String get ctErrorPayloadDatabaseMustBeString => 'payload.database deve ser uma string.';

  @override
  String get ctErrorPayloadDatabaseCannotBeEmpty => 'payload.database nao pode ficar vazio.';

  @override
  String get ctPermissionRead => 'Read';

  @override
  String get ctPermissionUpdate => 'Update';

  @override
  String get ctPermissionDelete => 'Delete';

  @override
  String get ctRuleTypeTable => 'Tabela';

  @override
  String get ctRuleTypeView => 'View';

  @override
  String get ctRuleTypeUnknown => 'Desconhecido';

  @override
  String get ctRuleEffectAllow => 'Permitir';

  @override
  String get ctRuleEffectDeny => 'Negar';

  @override
  String get ctDialogDismissCreateToken => 'Dispensar dialogo de criacao de token';

  @override
  String get ctDialogDismissRule => 'Dispensar dialogo de regra';

  @override
  String get ctPermissionDdl => 'DDL';

  @override
  String get ctGlobalScopeRulesDisabled =>
      'O escopo global esta ativo. As regras por recurso ficam ocultas e serao removidas ao salvar este token.';

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
  String get connectionStatusHubReconnectingSigningIn => 'Hub: A iniciar sessão novamente...';

  @override
  String get connectionStatusHubReconnectingSocket => 'Hub: A restabelecer ligação...';

  @override
  String get connectionStatusHubReconnectingWaitingHub => 'Hub: A aguardar o servidor...';

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

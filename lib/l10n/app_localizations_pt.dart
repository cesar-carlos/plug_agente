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
  String get dashboardDescription =>
      'Monitore o status do seu agente e conexões de banco de dados aqui.';
}

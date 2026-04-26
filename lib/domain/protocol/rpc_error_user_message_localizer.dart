/// Pluggable localizer for RPC user_message strings.
///
/// The default implementation returns Portuguese strings (preserving the
/// previous behaviour of [`RpcErrorCode.getUserMessage`]). Presentation-layer
/// code can install an `AppLocalizations`-backed localizer at boot time so
/// `error.data.user_message` carries strings in the active locale.
abstract class RpcErrorUserMessageLocalizer {
  String invalidRequest();
  String methodNotFound();
  String authenticationFailed();
  String unauthorized();
  String timeout();
  String invalidPayload();
  String networkError();
  String rateLimited();
  String replayDetected();
  String sqlValidationFailed();
  String sqlExecutionFailed();
  String connectionPoolExhausted();
  String resultTooLarge();
  String databaseConnectionFailed();
  String invalidDatabaseConfig();
  String executionNotFound();
  String executionCancelled();
  String internalError();
}

/// Built-in PT-BR fallback so the codebase stays self-contained when no
/// presentation-layer localizer is installed (e.g. headless tests).
class DefaultPtRpcErrorUserMessageLocalizer implements RpcErrorUserMessageLocalizer {
  const DefaultPtRpcErrorUserMessageLocalizer();

  @override
  String invalidRequest() => 'Requisição inválida. Revise os dados enviados.';

  @override
  String methodNotFound() => 'Método não suportado por esta versão do agente.';

  @override
  String authenticationFailed() => 'Falha de autenticação. Gere um novo token e tente novamente.';

  @override
  String unauthorized() => 'Você não tem permissão para executar esta operação.';

  @override
  String timeout() => 'A operação excedeu o tempo limite. Tente novamente.';

  @override
  String invalidPayload() => 'Falha ao processar os dados da requisição.';

  @override
  String networkError() => 'Conexão com o hub foi perdida. Tente novamente.';

  @override
  String rateLimited() => 'Muitas requisições em pouco tempo. Aguarde e tente novamente.';

  @override
  String replayDetected() => 'Requisição duplicada detectada. Gere um novo ID e tente novamente.';

  @override
  String sqlValidationFailed() => 'Comando SQL inválido. Revise a consulta enviada.';

  @override
  String sqlExecutionFailed() => 'Falha ao executar o comando SQL.';

  @override
  String connectionPoolExhausted() => 'Limite de conexões atingido. Aguarde e tente novamente.';

  @override
  String resultTooLarge() => 'Resultado muito grande. Aplique filtros e tente novamente.';

  @override
  String databaseConnectionFailed() => 'Não foi possível conectar ao banco de dados.';

  @override
  String invalidDatabaseConfig() => 'Configuração do banco inválida. Revise os dados de conexão.';

  @override
  String executionNotFound() => 'Execução não encontrada. Pode ter sido finalizada ou nunca iniciada.';

  @override
  String executionCancelled() => 'Execução cancelada pelo usuário.';

  @override
  String internalError() => 'Falha interna no processamento da requisição.';
}

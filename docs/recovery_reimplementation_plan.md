# Plano de Recodificacao Incremental

## Objetivo

Recuperar, em partes e com seguranca, todas as alteracoes que existiam no snapshot de hoje antes do rollback, reimplementando sobre a `main` e testando ao fim de cada etapa para identificar exatamente onde uma regressao volta a aparecer.

## Referencia de comparacao

- Base atual para reconstruir: `main`
- Snapshot de referencia: `wip/2026-04-01-before-rollback`
- Recorte da feature principal: `722f2c8..be825fd`
- Recorte dos ajustes posteriores e debug: `be825fd..wip/2026-04-01-before-rollback`

## Inventario do que foi feito hoje

## Classificacao de prioridade e natureza

### Legenda

- `Obrigatorio`: precisa voltar para recuperar comportamento ou feature perdida
- `Opcional`: pode ser reintroduzido depois, sem bloquear a recuperacao principal
- `Refatoracao a validar`: so reintroduzir se houver ganho real
- `Debug temporario`: usar apenas para diagnostico, nao como parte fixa da recuperacao

### Classificacao geral

- [ ] `Obrigatorio` Contrato `agent.getProfile`
- [ ] `Obrigatorio` Schema e validacao de `AgentProfile`
- [ ] `Obrigatorio` Persistencia do profile dentro de `Config`
- [ ] `Obrigatorio` Integracao com `OpenCnpjClient`
- [ ] `Obrigatorio` Integracao com `ViaCepClient`
- [ ] `Obrigatorio` Nova tela `AgentProfilePage`
- [ ] `Obrigatorio` Nova rota e navegacao para o profile
- [ ] `Obrigatorio` Testes principais de schema, RPC, repository, clients e page
- [ ] `Refatoracao a validar` Ajustes de formularios compartilhados
- [ ] `Obrigatorio` Startup com preferencias de janela
- [ ] `Obrigatorio` Comportamento de `window_manager`
- [ ] `Obrigatorio` Comportamento de `tray_manager`
- [ ] `Refatoracao a validar` Ajustes no shell principal e roteamento
- [ ] `Refatoracao a validar` Ajustes finos nos widgets de formulario
- [ ] `Debug temporario` Instrumentacao de debug
- [ ] `Obrigatorio` Testes e validacoes manuais de tray/startup

### Bloco A: feature funcional principal

- [ ] Contrato `agent.getProfile`
- [ ] Schema e validacao de `AgentProfile`
- [ ] Persistencia do profile dentro de `Config`
- [ ] Integracao com `OpenCnpjClient`
- [ ] Integracao com `ViaCepClient`
- [ ] Nova tela `AgentProfilePage`
- [ ] Nova rota e navegacao para o profile
- [ ] Ajustes de formularios compartilhados
- [ ] Testes de schema, RPC, clients, repository e page

Arquivos-chave:

- `lib/application/validation/agent_profile_schema.dart`
- `lib/application/rpc/rpc_method_dispatcher.dart`
- `lib/infrastructure/validation/rpc_contract_validator.dart`
- `lib/infrastructure/validation/rpc_request_schema_validator.dart`
- `lib/domain/entities/config.dart`
- `lib/infrastructure/repositories/agent_config_repository.dart`
- `lib/infrastructure/external_services/open_cnpj_client.dart`
- `lib/infrastructure/external_services/via_cep_client.dart`
- `lib/presentation/pages/agent_profile_page.dart`
- `lib/presentation/providers/config_provider.dart`

### Bloco B: ajustes posteriores e diagnostico

- [ ] Startup com preferencias de janela
- [ ] Comportamento de `window_manager`
- [ ] Comportamento de `tray_manager`
- [ ] Ajustes no shell principal e roteamento
- [ ] Ajustes finos nos widgets de formulario
- [ ] Instrumentacao de debug sob demanda
- [ ] Testes e validacoes manuais de tray/startup

Arquivos-chave:

- `lib/presentation/boot/app_initializer.dart`
- `lib/core/services/window_manager_service.dart`
- `lib/core/services/tray_manager_service.dart`
- `lib/presentation/app/app.dart`
- `lib/presentation/boot/app_root.dart`
- `lib/presentation/pages/main_window.dart`
- `lib/presentation/pages/dashboard_page.dart`
- `lib/core/debug/debug_session_logger.dart`

## Ordem de reimplementacao

## Estrategia de execucao

- [ ] Trabalhar sempre em uma branch nova de recuperacao a partir da `main`
- [ ] Implementar uma etapa por vez
- [ ] Ao final de cada etapa, rodar apenas os testes daquela fatia
- [ ] So avancar para a etapa seguinte se a etapa atual estiver estavel
- [ ] Se uma regressao aparecer, parar na etapa atual e nao misturar correcoes com a etapa seguinte
- [ ] Em toda parte que antes foi refatorada, revisar antes de reaplicar
- [ ] So reaplicar refatoracao se houver ganho real de clareza, manutencao, reuso, testabilidade ou comportamento
- [ ] Se a refatoracao nao trouxer ganho claro, preferir manter a estrutura atual da `main`

## Lembrete para partes refatoradas

- [ ] Antes de recodificar qualquer refatoracao, responder: isso simplifica o codigo ou so move complexidade de lugar
- [ ] Confirmar se a refatoracao reduz duplicacao real ou apenas cria mais abstracao
- [ ] Confirmar se melhora a leitura do fluxo principal
- [ ] Confirmar se facilita teste, manutencao ou evolucao futura
- [ ] Confirmar se nao aumenta o risco no startup, tray, navegacao ou formularios
- [ ] Se a resposta for incerta, implementar primeiro sem a refatoracao e comparar depois

## Sequencia sugerida de commits

- [ ] Commit 1: `feat(agent-profile): add schema and rpc contract`
- [ ] Commit 2: `feat(agent-profile): persist profile and external lookups`
- [ ] Commit 3: `feat(forms): add field specs and brazilian formatters`
- [ ] Commit 4: `feat(agent-profile): add page route and provider flow`
- [ ] Commit 5: `feat(desktop): restore startup and tray behavior`
- [ ] Commit 6: `chore(debug): add temporary runtime instrumentation` somente se preciso

### Etapa 1: contrato e validacao

**Status:** concluida na branch `recovery/agent-profile-etapa1` (2026-04-01).

**Nota:** o snapshot completo dos validators (`rpc_contract_validator` / `rpc_request_schema_validator` a partir do `wip`) nao encaixa na `main` por divergencias de protocolo. Foi feito merge manual: `agent.getProfile` no request validator, `profile` opcional em `validateAgentRegister` + `_validateAgentProfile`, sem puxar refactors grandes do `wip`.

**Incluido alem do plano original:** `Config` com campos de perfil, Drift e `AgentConfigRepository` mapeando esses campos, porque `agent.getProfile` usa `getCurrentConfig()` e `AgentProfile.fromConfig` — sem isso o RPC nao fecha.

- [x] Recriar `lib/application/validation/agent_profile_schema.dart`
- [x] Reaplicar os ajustes de `lib/application/validation/input_validators.dart`
- [x] Reaplicar os ajustes de `lib/infrastructure/validation/rpc_contract_validator.dart`
- [x] Reaplicar os ajustes de `lib/infrastructure/validation/rpc_request_schema_validator.dart`
- [x] Reintroduzir `agent.getProfile` em `lib/application/rpc/rpc_method_dispatcher.dart`
- [x] Atualizar os schemas em `docs/communication/schemas/`
- [x] Atualizar `docs/communication/openrpc.json`

Subpartes recomendadas:

- [x] Criar primeiro apenas a estrutura de `AgentProfile` e `AgentProfileAddress`
- [x] Reintroduzir as validacoes de CPF, CNPJ, CEP, telefone, celular e UF
- [x] Reintroduzir `fromFormFields`, `fromConfig`, `fromRpcPayload` e `applyToConfig`
- [x] Depois ligar o schema ao `rpc_request_schema_validator`
- [x] Depois ligar o retorno ao `rpc_method_dispatcher`

Checklist de teste:

- [x] Rodar os testes de schema e validators
- [x] Rodar os testes de dispatcher/RPC
- [x] Confirmar que `agent.getProfile` aceita e retorna o payload esperado
- [x] Confirmar que um payload invalido falha com mensagem acionavel

Ponto de parada:

- [x] A etapa termina quando o contrato RPC funciona sem depender da UI

**Comandos de teste usados:**

```text
flutter test test/application/validation/agent_profile_schema_test.dart test/application/rpc/rpc_method_dispatcher_test.dart test/infrastructure/validation/rpc_contract_validator_outgoing_test.dart test/infrastructure/validation/rpc_request_schema_validator_test.dart
flutter analyze
```

### Etapa 2: persistencia e integracoes

**Ja aplicado na Etapa 1** (necessario para `agent.getProfile`): `Config` com campos de perfil, `agent_config_drift_database` (+ `.g.dart`), `agent_config_repository`, `agent_config_data_source`.

**Pendente para a proxima rodada:** clients HTTP de CNPJ/CEP e DI.

- [x] Reaplicar os campos do profile em `lib/domain/entities/config.dart`
- [x] Reaplicar `lib/infrastructure/datasources/agent_config_data_source.dart`
- [x] Reaplicar `lib/infrastructure/repositories/agent_config_repository.dart`
- [x] Reaplicar `lib/infrastructure/repositories/agent_config_drift_database.dart`
- [x] Regenerar o arquivo derivado do Drift se necessario
- [ ] Recriar `lib/infrastructure/external_services/open_cnpj_client.dart`
- [ ] Recriar `lib/infrastructure/external_services/via_cep_client.dart`
- [ ] Ajustar `lib/infrastructure/external_services/dio_factory.dart`
- [ ] Ajustar o registro de dependencias em `lib/core/di/plug_dependency_registrar.dart`

Subpartes recomendadas:

- [ ] Comecar pelos campos novos em `Config`
- [ ] Depois ajustar datasource e repository para salvar e ler esses campos
- [ ] So depois adicionar os clients externos
- [ ] Por ultimo registrar tudo no DI

Arquivos de teste para priorizar:

- [ ] `test/application/validation/agent_profile_schema_test.dart`
- [ ] `test/infrastructure/external_services/open_cnpj_client_test.dart`
- [ ] `test/infrastructure/external_services/via_cep_client_test.dart`

Checklist de teste:

- [ ] Rodar testes dos clients
- [ ] Rodar testes do repository
- [ ] Validar salvar e recarregar o profile sem depender da tela completa
- [ ] Validar que a serializacao nao quebrou configs antigas

Ponto de parada:

- [ ] A etapa termina quando os dados do profile persistem corretamente sem navegar pela UI

### Etapa 3: componentes compartilhados de formulario

- [ ] Recriar `lib/shared/widgets/common/form/field_spec.dart`
- [ ] Recriar `lib/shared/widgets/common/form/app_field_specs.dart`
- [ ] Recriar `lib/shared/widgets/common/form/brazilian_field_formatters.dart`
- [ ] Reaplicar ajustes em `lib/shared/widgets/common/form/app_text_field.dart`
- [ ] Reaplicar ajustes em `lib/shared/widgets/common/form/app_dropdown.dart`
- [ ] Reaplicar ajustes em `lib/shared/widgets/common/form/numeric_field.dart`
- [ ] Reaplicar ajustes em `lib/shared/widgets/common/form/password_field.dart`
- [ ] Atualizar `lib/shared/widgets/common/form_components.dart`

Subpartes recomendadas:

- [ ] Criar primeiro `field_spec.dart`
- [ ] Depois criar `app_field_specs.dart`
- [ ] Depois criar `brazilian_field_formatters.dart`
- [ ] So entao adaptar `app_text_field.dart` e `app_dropdown.dart`
- [ ] Deixar `numeric_field.dart` e `password_field.dart` por ultimo

Arquivos mais sensiveis nesta etapa:

- [ ] `lib/shared/widgets/common/form/app_text_field.dart`
- [ ] `lib/shared/widgets/common/form/app_dropdown.dart`

Checklist de teste:

- [ ] Validar mascara de CPF/CNPJ
- [ ] Validar mascara de CEP
- [ ] Validar mascara de telefone e celular
- [ ] Validar normalizacao de UF
- [ ] Fazer smoke test manual na tela de configuracao

Ponto de parada:

- [ ] A etapa termina quando os componentes de formulario funcionam sem alterar tray/startup

### Etapa 4: tela e navegacao do Agent Profile

- [ ] Recriar `lib/presentation/pages/agent_profile_page.dart`
- [ ] Reaplicar ajustes em `lib/presentation/providers/config_provider.dart`
- [ ] Reaplicar ajustes em `lib/presentation/pages/config/config_form_controller.dart`
- [ ] Reaplicar alteracoes em `lib/core/routes/app_routes.dart`
- [ ] Reaplicar alteracoes em `lib/core/routes/app_router.dart`
- [ ] Reaplicar alteracoes em `lib/presentation/pages/main_window.dart`
- [ ] Ajustar textos em `lib/core/constants/app_strings.dart`
- [ ] Atualizar localizacao em `lib/l10n/`

Subpartes recomendadas:

- [ ] Primeiro adaptar `ConfigProvider` e `ConfigFormController`
- [ ] Depois introduzir a nova rota em `app_routes.dart`
- [ ] Depois ligar a rota em `app_router.dart`
- [ ] So depois conectar `main_window.dart`
- [ ] Por ultimo criar e estilizar a `AgentProfilePage`

Arquivos de teste para priorizar:

- [ ] `test/core/routes/app_routes_test.dart`
- [ ] `test/presentation/pages/agent_profile_page_test.dart`

Checklist de teste:

- [ ] Abrir a rota do Agent Profile sem quebrar o shell
- [ ] Validar lookup de CNPJ
- [ ] Validar lookup de CEP
- [ ] Validar salvar profile
- [ ] Validar reabrir dados salvos
- [ ] Rodar `test/presentation/pages/agent_profile_page_test.dart`

Ponto de parada:

- [ ] A etapa termina quando a feature inteira funciona na `main` sem o bloco de tray/startup novo

### Etapa 5: startup e tray

- [ ] Reaplicar a resolucao de preferencias de startup em `lib/presentation/boot/app_initializer.dart`
- [ ] Reaplicar o comportamento de janela em `lib/core/services/window_manager_service.dart`
- [ ] Reaplicar o comportamento do tray em `lib/core/services/tray_manager_service.dart`
- [ ] Reaplicar somente o necessario em `lib/presentation/app/app.dart`
- [ ] Reaplicar somente o necessario em `lib/presentation/boot/app_root.dart`
- [ ] Revisar o impacto em `lib/presentation/pages/dashboard_page.dart`
- [ ] Revisar o impacto em `lib/presentation/pages/main_window.dart`
- [ ] Adicionar ou atualizar `test/presentation/boot/app_initializer_test.dart`

Subpartes recomendadas:

- [ ] Passo 5.1: reintroduzir apenas a leitura das preferencias em `app_initializer.dart`
- [ ] Passo 5.2: reintroduzir apenas o comportamento de `window_manager_service.dart`
- [ ] Passo 5.3: reintroduzir apenas a inicializacao basica do `tray_manager_service.dart`
- [ ] Passo 5.4: reintroduzir clique esquerdo para restaurar janela
- [ ] Passo 5.5: reintroduzir clique direito para menu de contexto
- [ ] Passo 5.6: revisar impactos em `app.dart`, `app_root.dart`, `main_window.dart` e `dashboard_page.dart`

Arquivos mais suspeitos nesta etapa:

- [ ] `lib/presentation/boot/app_initializer.dart`
- [ ] `lib/core/services/window_manager_service.dart`
- [ ] `lib/core/services/tray_manager_service.dart`
- [ ] `lib/presentation/app/app.dart`
- [ ] `lib/presentation/boot/app_root.dart`
- [ ] `lib/presentation/pages/main_window.dart`

Checklist de teste:

- [ ] Iniciar com `start_minimized: false`
- [ ] Iniciar com `start_minimized: true`
- [ ] Validar `minimize_to_tray: true`
- [ ] Validar `close_to_tray: true`
- [ ] Confirmar que clique esquerdo no tray restaura a UI
- [ ] Confirmar que clique direito no tray abre o menu
- [ ] Confirmar que minimizar envia para a bandeja
- [ ] Confirmar que fechar envia para a bandeja

Ponto de parada:

- [ ] Se a UI travar, parar imediatamente na ultima subparte aplicada
- [ ] Registrar qual subparte reintroduziu a regressao
- [ ] Nao seguir para a proxima subparte ate isolar a causa

### Etapa 6: instrumentacao somente se houver regressao

- [ ] Recriar `lib/core/debug/debug_session_logger.dart` apenas se necessario
- [ ] Adicionar logs em `lib/presentation/app/app.dart` apenas se necessario
- [ ] Adicionar logs em `lib/presentation/boot/app_root.dart` apenas se necessario
- [ ] Adicionar logs em `lib/core/routes/app_router.dart` apenas se necessario
- [ ] Adicionar logs em `lib/presentation/pages/main_window.dart` apenas se necessario
- [ ] Adicionar logs em `lib/presentation/pages/dashboard_page.dart` apenas se necessario

Checklist de teste:

- [ ] Validar se o problema reaparece sem instrumentacao
- [ ] Se reaparecer, adicionar logs em um ponto por vez
- [ ] Registrar exatamente em qual reintroducao a UI volta a travar

Ordem de instrumentacao:

- [ ] Logar primeiro `app_initializer.dart`
- [ ] Depois `app.dart`
- [ ] Depois `app_root.dart`
- [ ] Depois `app_router.dart`
- [ ] Depois `main_window.dart`
- [ ] Depois `dashboard_page.dart`

Ponto de parada:

- [ ] Remover ou isolar a instrumentacao assim que a causa for encontrada

## Ordem recomendada de execucao

- [ ] Concluir Etapa 1
- [ ] Concluir Etapa 2
- [ ] Concluir Etapa 3
- [ ] Concluir Etapa 4
- [ ] Validar o app funcionando com a feature reintroduzida
- [ ] Concluir Etapa 5 em subpassos pequenos
- [ ] Usar Etapa 6 apenas se a regressao voltar

## Arquivos mais suspeitos para a regressao

- [ ] `lib/presentation/boot/app_initializer.dart`
- [ ] `lib/core/services/window_manager_service.dart`
- [ ] `lib/core/services/tray_manager_service.dart`
- [ ] `lib/presentation/app/app.dart`
- [ ] `lib/presentation/boot/app_root.dart`
- [ ] `lib/presentation/pages/main_window.dart`

## Criterio de sucesso

- [ ] Todo o bloco funcional do Agent Profile foi recuperado
- [ ] O app continua abrindo normalmente na `main`
- [ ] O comportamento de tray foi reintroduzido sem travar a UI
- [ ] Sabemos exatamente em qual etapa qualquer regressao reaparece

## Registro de execucao

### Rodada 1

- [ ] Etapa iniciada
- [ ] Testes executados
- [ ] Resultado registrado
- [ ] Pode avancar

### Rodada 2

- [ ] Etapa iniciada
- [ ] Testes executados
- [ ] Resultado registrado
- [ ] Pode avancar

### Rodada 3

- [ ] Etapa iniciada
- [ ] Testes executados
- [ ] Resultado registrado
- [ ] Pode avancar

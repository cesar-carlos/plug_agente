# Testing

## Instalação manifest e encerramento cooperativo — 2026-10-25

Regressões novas cobrem preparação concorrente, fechamento único, cancelamento,
falha de manutenção, resposta de fechamento perdida e descarte durante consulta.
O contrato nativo executa cliente/servidor próprios do teste, valida namespace,
operação, consulta sem efeitos, cancelamento e recuperação. A persistência nativa
confere DACL preservada, falha de escrita e falha de substituição com evidência.
Fixtures Pascal verificam a proibição de migração silenciosa/sem administrador ou
com tentativa anterior. Tooling verifica padrão manifest e opções conflitantes.

Comandos locais (sem instalação):

```text
flutter test --exclude-tags "live || slow || perf"
flutter test test/application/services/installation_preparation_service_test.dart test/infrastructure/services/windows_installation_preparation_monitor_test.dart test/installer/setup_script_test.dart
dart analyze lib test
python -m unittest discover -s tool/updater -p "test_*.py"
python -m unittest discover -s tool/release -p "test_*.py"
python tool/release/release_preflight.py --early --allow-dirty --allow-existing-tag --compile-iss
ctest --test-dir build/windows/x64/updater -C Debug --output-on-failure --no-tests=error
flutter build windows --debug --no-pub
```

A homologação instalada exige fixture privada nova vinculada à revisão final,
conferida antes/depois de cada fase e autorização administrativa própria. Cobrir
Windows 10/11/Server, usuário padrão/administrador distinto, UAC cancelado,
versões antigas abertas, PID reutilizado, acesso remoto/negado, múltiplas sessões
e instalações, falhas de SQLite/ODBC, resposta perdida, reboot, logout/RDP,
apply/probation/rollback e restauração de binários/WAL/schema/segredos na conta
original. Medir 20 updates completos (processos, handles, locks, snapshots);
prepare/cancel não substitui essa prova. Consulte a
[evolução](../implemente/plano_auto_update_evolution.md) para evidências e pendências.
Rules canônicas: [índice](../../.cursor/rules/rules_index.mdc) e
[contratos locais](../../.cursor/rules/project_specifics.mdc).

Guias de configuracao e estrategia para testes E2E, integracao e
concorrencia. Unitarios e widget tests: `.cursor/rules/testing.mdc` e
`.cursor/rules/testing_dart_flutter.mdc`.

## E2E

Indice central (pre-requisitos, preflight, como rodar, familias):
[e2e_setup.md](e2e_setup.md).

## Outros

| Arquivo | Quando consultar |
| --- | --- |
| [sql_queue_concurrency_tests.md](sql_queue_concurrency_tests.md) | Estrategia de testes para `SqlExecutionQueue` + `QueuedDatabaseGateway` |
| [single_instance_multiuser.md](single_instance_multiuser.md) | Cenarios manuais de instancia unica em multi-usuario Windows |

## Opt-in

Testes com API/ODBC/Hub reais sao opt-in via `RUN_LIVE_*` / `RUN_ODBC_*` /
`ODBC_E2E_*`. Registro Windows real:
`RUN_LIVE_STARTUP_REGISTRY_TESTS` (secao em [e2e_setup.md](e2e_setup.md)).
Helper: `test/helpers/e2e_env.dart` (`E2EEnv`). Sem variaveis → `skip` com
mensagem clara.

Atalhos: `dart run tool/e2e/check_e2e_env.dart`,
`python tool/agent_actions/run_agent_actions_operational_gate.py`,
`python tool/odbc/run_odbc_operational_validation.py`.

## Regressao do auto-update — 2026-10-25

As suites de scheduler, instalador privilegiado, service pending, download/apply,
probe e manutencao cobrem timers obsoletos, cancelamento, falha de persistencia com
cache atualizado, reconciliacao sem novo despacho e timeout de snapshot. A suite
`test/infrastructure/services/appcast_transport_test.dart` cobre limite exato,
excesso em streaming, redirects, cancelamento, prazo total e XML invalido. Testes
de provider e diagnosticos cobrem resposta tardia e rotulo localizado de recuperacao.

Validacao integrada:

```powershell
flutter test --no-pub --exclude-tags 'live || slow || perf'
flutter analyze --no-pub
python -m unittest tool.appcast.test_appcast_manager tool.appcast.test_validate_release tool.appcast.test_appcast_signing tool.release.test_publish_release -v
flutter build windows --debug --no-pub
```

Use Python com `cryptography` instalado. Build Debug nao e instalador de release.
Resultados desta revisao e limites de homologacao ficam no
[documento de evolucao](../implemente/plano_auto_update_evolution.md).

A rodada de fechamento das cinco lacunas acrescenta regressao de corrupcao do
arquivo global e tipo do pending, reinicio sem perder evidencia, apply/cancel do
helper concorrentes, status legado sem timestamp, preparacao com resposta perdida,
metricas/callbacks que lancam excecoes e recuperacao no boot. Os testes de settings
agora exigem preservar arquivos invalidos e recusar sobrescrita. Evidencias da
rodada: `build/update-five-gaps-red.log`, `build/update-five-gaps-green.log`,
`build/update-five-gaps-suite-final.log`, `build/update-five-gaps-analysis-final.log`
e `build/update-five-gaps-windows.log`.
A matriz instalada pendente permanece no documento de evolucao; skips e build
Debug nao aprovam nenhum dos seus itens.

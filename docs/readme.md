# Documentacao - Plug Agente

Indice principal da documentacao do projeto. Cada subpasta tem o proprio
`readme.md` com detalhes de quando consultar cada arquivo.

## Estrutura

```text
docs/
|- readme.md
|- project_overview.md
|- architecture/
|  |- readme.md
|  |- QUICKSTART.md
|  |- performance_reliability_improvements.md
|  |- odbc_worker_evaluation_criteria.md
|  \- odbc_operational_validation_runbook.md
|- communication/
|  |- readme.md
|  |- socket_communication_standard.md
|  |- socket_agent_actions.md
|  |- socketio_client_binary_transport.md
|  |- socket_communication_roadmap.md
|  |- socket_communication_backlog.md
|  |- openrpc.json
|  \- schemas/
|- database/
|  |- readme.md
|  |- sql_anywhere_connection.md
|  |- sql_server_connection.md
|  \- postgresql_connection.md
|- implemente/
|  |- readme.md
|  |- plano_acoes_agendadas_execucoes.md
|  |- plano_auto_update_evolution.md
|  \- acoes/
|- install/
|  |- readme.md
|  |- installation_guide.md
|  |- requirements.md
|  |- release_guide.md
|  \- auto_update_setup.md
|- security/
|  \- auto_update_threat_model.md
\- testing/
   |- readme.md
   |- e2e_setup.md
   |- e2e_api.md
   |- e2e_hub.md
   |- e2e_actions.md
   |- e2e_odbc.md
   |- single_instance_multiuser.md
   \- sql_queue_concurrency_tests.md
```

## Links rapidos

- [Visao geral do agente](project_overview.md)
- [Padrao de comunicacao Socket atual](communication/socket_communication_standard.md)
- [Guia de cliente Socket com transporte binario](communication/socketio_client_binary_transport.md)
- [OpenRPC do agente](communication/openrpc.json)
- [Quick start de performance/confiabilidade](architecture/QUICKSTART.md)
- [Configuracao de testes E2E](testing/e2e_setup.md)
- [Connection strings ODBC por driver](database/readme.md)
- [Guia de instalacao](install/readme.md)

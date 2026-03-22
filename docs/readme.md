# Documentacao - Plug Agente

Indice principal da documentacao do projeto.

## Estrutura

```text
docs/
|- readme.md
|- project_overview.md
|- communication/
|  |- socket_communication_standard.md
|  |- socketio_client_binary_transport.md
|  |- openrpc.json
|  \- schemas/
|- install/
|  |- readme.md
|  |- installation_guide.md
|  |- requirements.md
|  |- path_setup.md
|  |- release_guide.md
|  |- auto_update_setup.md
|  |- testing_auto_update.md
|  \- version_strategy.md
|- testing/
|  \- e2e_setup.md
|- notes/
|  \- performance_benchmark_strategy.md
```

## Links rapidos

- [Visao geral do ecossistema](project_overview.md)
- [Padrao de comunicacao Socket atual](communication/socket_communication_standard.md)
- [Guia de cliente Socket com transporte binario](communication/socketio_client_binary_transport.md)
- [OpenRPC do agente](communication/openrpc.json)
- [Guia de instalacao](install/readme.md)
- [Testes E2E, `.env` e benchmarks](testing/e2e_setup.md)
- [Estrategia de performance / benchmarks](notes/performance_benchmark_strategy.md)
- [Benchmarks (JSONL, comandos)](../benchmark/README.md)

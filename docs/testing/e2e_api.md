# E2E - API tests

Testes E2E que consomem a API HTTP do hub. Os testes basicos do agente
(login/refresh) estao em `test/infrastructure/external_services/api_test.dart`
(tag `live`).

Index geral: [e2e_setup.md](e2e_setup.md).

## Variaveis

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_API_TESTS` | Sim | `true` para executar testes de API |
| `API_TEST_BASE_URL` | Sim | URL base HTTP(S) do hub (ex.: `http://host:port/`); sem ela o teste e ignorado |
| `API_TEST_TIMEOUT_URL` | Nao | URL para teste de timeout (default: IP nao roteavel) |

## Executar

```bash
flutter test test/infrastructure/external_services/api_test.dart
```

Sem `RUN_LIVE_API_TESTS=true` e um `API_TEST_BASE_URL` http(s) valido, o
ficheiro e ignorado com mensagem clara.

# E2E - API tests

Testes E2E que consomem a API HTTP do hub. Os testes basicos do agente
(login/refresh) estao em `test/infrastructure/external_services/api_test.dart`.

Index geral: [e2e_setup.md](e2e_setup.md).

## Variaveis

| Variavel | Obrigatoria | Descricao |
| -------- | ----------- | --------- |
| `RUN_LIVE_API_TESTS` | Sim | `true` para executar testes de API |
| `API_TEST_BASE_URL` | Nao | URL base (default: `http://31.97.29.223:3000/`) |
| `API_TEST_TIMEOUT_URL` | Nao | URL para teste de timeout (default: IP nao roteavel) |

## Executar

```bash
flutter test test/infrastructure/external_services/api_test.dart
```

Sem `RUN_LIVE_API_TESTS=true`, o ficheiro e ignorado com mensagem clara.

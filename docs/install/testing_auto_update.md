# Guia de Teste - Auto-Update (1h + silencioso)

Validação do fluxo automático no Windows com appcast Sparkle (HTTPS) + GitHub.

## Pré-requisitos

1. Feed configurado por uma das opções:
   - build com `--dart-define=AUTO_UPDATE_FEED_URL=...` (recomendado para release)
   - `.env` com feed configurado (fallback local)

   ```env
   AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
   ```

2. Release publicado com instalador `PlugAgente-Setup-*.exe`.
3. Workflow `Update Appcast on Release` concluído com sucesso.

## Teste rápido (manual sob demanda)

1. Execute uma versão antiga instalada do app.
2. Abra **Configurações** > **Atualizações**.
3. Clique em **Verificar atualizações**.
4. Resultado esperado:
   - com nova versão: download/aplicação iniciam silenciosamente;
   - sem nova versão: feedback de “sem atualização”.

> Dica: o feed em `raw.githubusercontent.com` pode ficar em cache por até 5 minutos após publicar release.
> Se acabou de publicar, aguarde alguns minutos e repita a checagem manual.

> Observação: o fluxo foi implementado para ser silencioso; não depende de
> prompt/modal para avançar.

## Teste end-to-end do fluxo automático

1. Garanta uma instalação em versão antiga (ex.: `1.0.1`).
2. Publique nova versão (ex.: `1.0.2`) e anexe `PlugAgente-Setup-1.0.2.exe`.
3. Aguarde o workflow atualizar `appcast.xml`.
4. Inicie a versão antiga e mantenha o app em execução.
5. Valide:
   - checagem inicial em background ao subir o app;
   - nova checagem automática a cada 1h;
   - ao detectar update, app baixa/aplica sem ação do usuário;
   - reinício automático quando suportado pelo ambiente.

## Verificações úteis

- Feed:
  - `https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml`
  - `https://cesar-carlos.github.io/plug_agente/appcast.xml` (se usar Pages)
- Actions:
  - workflow de appcast executado no release publicado
- Logs:
  - `auto_update_orchestrator` no log da aplicação

## Falhas comuns

### Workflow não executou

- Release sem asset `PlugAgente-Setup-{versao}.exe` compatível com a tag.
- O workflow publica o appcast **sem** `sparkle:dsaSignature` (comportamento esperado).

### Feed não configurado

- Defina `AUTO_UPDATE_FEED_URL` no build (`--dart-define`) ou no `.env`.

### appcast sem item

- Confirme upload do asset `.exe` no release.
- Confirme nome esperado do instalador (`PlugAgente-Setup-*.exe`).

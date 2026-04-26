# Auto-Update

Configuração e validação do update automático do Plug Agente no Windows.

## Visão Geral

O app usa `auto_updater`/WinSparkle com feed Sparkle em XML. O recurso só fica
ativo quando `AUTO_UPDATE_FEED_URL` aponta para uma URL `.xml` e o runtime
suporta auto-update.

Ordem de resolução:

1. `--dart-define=AUTO_UPDATE_FEED_URL=...` no build de release.
2. `.env` em runtime para desenvolvimento e testes locais.

Em modo degradado, o auto-update fica desabilitado e a UI exibe uma mensagem
informativa.

## Feed Oficial

```text
https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

Para release, `python installer/build_installer.py` injeta o feed via
`--dart-define` quando o `.env` contém:

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

## Workflow de Publicação

1. Gere o instalador com `python installer/build_installer.py`.
2. Publique uma release seguindo [release_guide.md](release_guide.md).
3. O workflow **Update Appcast on Release** valida versão, tag e asset.
4. O workflow atualiza `appcast.xml` em `main`.
5. O smoke check confirma que o feed publicado aponta para o asset esperado.

O asset deve seguir:

```text
PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

## Comportamento no App

- Checagem inicial em background ao subir o app.
- Checagem automática a cada 1 hora, no mínimo.
- Checagem manual pela UI em fluxo foreground do WinSparkle.
- Download/aplicação silenciosos quando o ambiente suporta.
- Atualização aplicada quando o app encerra ou quando o updater solicita quit.

## Teste Rápido

1. Instale uma versão antiga.
2. Abra **Configurações** > **Atualizações**.
3. Clique em **Verificar atualizações**.
4. Valide:
   - com versão nova: download/aplicação iniciam;
   - sem versão nova: a UI informa que não há atualização.

O endpoint `raw.githubusercontent.com` pode ficar em cache por alguns minutos
após a publicação da release.

## Teste End-to-End

1. Instale uma versão antiga, por exemplo `1.2.6`.
2. Publique nova versão, por exemplo `1.2.7`, com o asset correto.
3. Aguarde o workflow atualizar `appcast.xml`.
4. Inicie a versão antiga.
5. Verifique logs de `auto_update_orchestrator`.
6. Valide a checagem inicial, uma checagem manual e o comportamento de aplicação
   do update.

## Falhas Comuns

### Workflow não executou

- Release sem asset `PlugAgente-Setup-{versao}.exe`.
- Asset com nome diferente da versão curta da tag.

### Versão fora de sincronia

- `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` divergem.
- Rode `python installer/update_version.py`, revise o diff e commite as
  alterações antes da tag.

### Feed não configurado

- Defina `AUTO_UPDATE_FEED_URL` no build ou no `.env`.
- A URL precisa terminar em `.xml`, ignorando query string.

### Feed publicado não reflete a release

- Aguarde cache do GitHub Raw.
- Confirme se o smoke check passou.
- Confira se o item mais recente do `appcast.xml` contém a versão e o asset
  esperados.

## Assinatura

O fluxo atual não publica `sparkle:dsaSignature` no `appcast.xml`. Para uso em
produção ampla, trate assinatura do instalador/executável como requisito de
distribuição, além das validações do feed.

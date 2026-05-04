# Auto-Update

Configuracao e validacao do update automatico do Plug Agente no Windows.

## Visao Geral

O app usa `auto_updater`/WinSparkle com feed Sparkle em XML. O recurso so fica
ativo quando `AUTO_UPDATE_FEED_URL` aponta para uma URL `.xml` e o runtime
suporta auto-update.

Ordem de resolucao:

1. `--dart-define=AUTO_UPDATE_FEED_URL=...` no build de release.
2. `.env` em runtime para desenvolvimento e testes locais.

Em modo degradado, o auto-update fica desabilitado e a UI exibe uma mensagem
informativa.

## Feed Oficial

```text
https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

Para release, `python installer/build_installer.py` injeta o feed via
`--dart-define` quando o `.env` contem:

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

## Workflow de Publicacao

1. Gere o instalador com `python installer/build_installer.py`.
2. Publique uma release seguindo [release_guide.md](release_guide.md).
3. O workflow **Update Appcast on Release** valida versao, tag e asset.
4. O workflow atualiza `appcast.xml` em `main`.
5. Se a secret `AUTO_UPDATE_DSA_PRIVATE_KEY_PEM` estiver configurada no GitHub,
   o workflow tambem publica `sparkle:dsaSignature` no `enclosure`.
6. O smoke check confirma que o feed publicado aponta para o asset esperado.

O asset deve seguir:

```text
PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

## Comportamento no App

- Checagem inicial em background ao subir o app.
- Checagem automatica a cada 1 hora, no minimo.
- Checagem manual pela UI em fluxo foreground do WinSparkle.
- O feed do updater e configurado uma vez por sessao na inicializacao do app.
- A checagem manual usa um probe HTTP com `cb=` apenas para diagnostico e
  bypass de cache; esse probe nao reconfigura o feed ja carregado pelo updater.
- O app persiste o ultimo diagnostico da checagem manual para suporte.
- Timeouts repetidos abrem um bloqueio temporario do check manual para evitar
  ficar preso em loops de callback perdido do plugin Windows.
- Download/aplicacao silenciosos quando o ambiente suporta.
- Atualizacao aplicada quando o app encerra ou quando o updater solicita quit.

## Teste Rapido

1. Instale uma versao antiga.
2. Abra **Configuracoes** > **Atualizacoes**.
3. Clique em **Verificar atualizacoes**.
4. Valide:
   - com versao nova: download/aplicacao iniciam;
   - sem versao nova: a UI informa que nao ha atualizacao;
   - com falha do updater: a UI fecha a checagem em tempo finito e mostra
     detalhes tecnicos.

O endpoint `raw.githubusercontent.com` pode ficar em cache por alguns minutos
apos a publicacao da release.

Ao validar manualmente o feed fora do app, prefira anexar um parametro de cache
como `?cb=<timestamp>` para evitar observar uma versao antiga do `appcast.xml`.

## Teste End-to-End

1. Instale uma versao antiga, por exemplo `1.2.6`.
2. Publique nova versao, por exemplo `1.2.7`, com o asset correto.
3. Aguarde o workflow atualizar `appcast.xml`.
4. Inicie a versao antiga.
5. Verifique logs de `auto_update_orchestrator`.
6. Valide a checagem inicial, uma checagem manual e o comportamento de aplicacao
   do update.

## Assinatura DSA

- A chave publica `dsa_pub.pem` deve ficar embutida em
  `windows/runner/Runner.rc`.
- Para assinar localmente o instalador e gerar o sidecar de appcast, use:

```env
AUTO_UPDATE_DSA_PRIVATE_KEY_PATH=C:/caminho/seguro/dsa_priv.pem
```

- Para exigir a assinatura no build local:

```env
AUTO_UPDATE_REQUIRE_DSA_SIGNATURE=true
```

- Para o feed oficial publicar `sparkle:dsaSignature`, configure a secret
  `AUTO_UPDATE_DSA_PRIVATE_KEY_PEM` no GitHub Actions.

## Falhas Comuns

### Workflow nao executou

- Release sem asset `PlugAgente-Setup-{versao}.exe`.
- Asset com nome diferente da versao curta da tag.

### Versao fora de sincronia

- `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` divergem.
- Rode `python installer/update_version.py`, revise o diff e commite as
  alteracoes antes da tag.

### Feed nao configurado

- Defina `AUTO_UPDATE_FEED_URL` no build ou no `.env`.
- A URL precisa terminar em `.xml`, ignorando query string.

### Feed publicado nao reflete a release

- Aguarde cache do GitHub Raw.
- Faca uma nova leitura com cache-busting, por exemplo `appcast.xml?cb=<timestamp>`.
- Confirme se o smoke check passou.
- Confira se o item mais recente do `appcast.xml` contem a versao e o asset
  esperados.

### Assinatura ausente

- Sem a secret `AUTO_UPDATE_DSA_PRIVATE_KEY_PEM`, o workflow continua
  publicando o feed, mas sem `sparkle:dsaSignature`.
- Sem `AUTO_UPDATE_DSA_PRIVATE_KEY_PATH`, o build local nao gera o sidecar de
  assinatura.

# Auto-Update

Configuracao, publicacao e diagnostico do update automatico do Plug Agente no
Windows.

## Visao Geral

O app usa `auto_updater`/WinSparkle com feed Sparkle em XML. O recurso fica
ativo quando:

- o runtime suporta auto-update;
- a URL final do feed termina em `.xml`.

Resolucao da URL do feed:

1. `--dart-define=AUTO_UPDATE_FEED_URL=...`
2. `.env` em runtime
3. feed oficial embutido no app

Feed oficial:

```text
https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

Se um override invalido for informado em `AUTO_UPDATE_FEED_URL`, o auto-update
fica indisponivel e a UI orienta remover o override para voltar ao feed oficial.

## Comportamento no App

- O feed do updater e configurado uma vez por sessao na inicializacao.
- Existe checagem inicial em background ao subir o app.
- Existe checagem automatica recorrente com intervalo minimo de 1 hora.
- A checagem manual usa um probe HTTP com `cb=` apenas para diagnostico e
  bypass de cache; esse probe nao reconfigura o feed do updater.
- O app persiste o ultimo diagnostico manual e o ultimo diagnostico automatico.
- Timeouts repetidos no fluxo manual abrem um bloqueio temporario para evitar
  loops de callback perdido do plugin Windows.
- Quando o runtime nao suporta auto-update, a UI informa isso explicitamente.

## Fonte de Verdade do Appcast

A logica de geracao, validacao e smoke check do `appcast.xml` fica em:

```text
tool/appcast_manager.py
```

O workflow `.github/workflows/update-appcast.yml` chama esse script para:

1. atualizar o feed;
2. validar o arquivo local;
3. validar o feed publicado.

Teste local rapido do script:

```bash
python -m unittest tool.test_appcast_manager -v
```

## Workflow de Publicacao

1. Gere o instalador com `python installer/build_installer.py`.
2. Publique uma release seguindo [release_guide.md](release_guide.md).
3. O workflow **Update Appcast on Release** valida tag, versao e asset.
4. O workflow atualiza `appcast.xml` em `main`.
5. O smoke check confirma que o feed publicado aponta para o asset esperado.

Nome esperado do asset:

```text
PlugAgente-Setup-{MAJOR.MINOR.PATCH}.exe
```

## Teste Operacional

1. Instale uma versao antiga.
2. Abra **Configuracoes** > **Atualizacoes**.
3. Valide a ultima checagem automatica, se existir.
4. Clique em **Verificar atualizacoes**.
5. Confirme:
   - com versao nova: download/aplicacao iniciam;
   - sem versao nova: a UI informa que nao ha atualizacao;
   - com falha do updater: a UI encerra em tempo finito e mostra detalhes tecnicos.

O endpoint `raw.githubusercontent.com` pode ficar em cache por alguns minutos
apos a publicacao. Ao validar manualmente o feed fora do app, prefira usar
`?cb=<timestamp>`.

## Falhas Comuns

### Feed override invalido

- Remova `AUTO_UPDATE_FEED_URL` para voltar ao feed oficial.
- Se precisar de um feed customizado, ele precisa terminar em `.xml`.

### Workflow nao executou

- Release sem asset `PlugAgente-Setup-{versao}.exe`.
- Asset com nome diferente da versao curta da tag.

### Versao fora de sincronia

- `pubspec.yaml`, `installer/setup.iss` e
  `lib/core/constants/app_version.g.dart` divergem.
- Rode `python installer/update_version.py`, revise o diff e commite antes da tag.

### Feed publicado nao reflete a release

- Aguarde o cache do GitHub Raw expirar.
- Refaca a leitura com `appcast.xml?cb=<timestamp>`.
- Confirme se o smoke check passou.
- Verifique se o item mais recente do `appcast.xml` aponta para a versao e o
  asset esperados.

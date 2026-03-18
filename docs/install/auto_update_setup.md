# Configuração de Atualização Automática

Este documento explica como configurar e testar o sistema de atualização automática do Plug Agente.

> **Nota**: Para instruções de como testar o auto-update, consulte [testing_auto_update.md](testing_auto_update.md).
> **Nota**: Para instruções de como criar releases, consulte [release_guide.md](release_guide.md).

## Visão Geral

O sistema de atualização automática permite que o aplicativo verifique e
instale atualizações automaticamente. Utiliza o pacote `auto_updater`
(WinSparkle no Windows) com feed no formato Sparkle.

Comportamento atual da aplicação:

- checagem automática em background a cada 1 hora;
- checagem inicial ao subir o app;
- fluxo silencioso de download/aplicação (sem interação obrigatória).

## Opção Recomendada: GitHub Releases + GitHub Raw

O projeto está configurado para usar **GitHub Releases** para hospedar os executáveis e **GitHub Raw** (ou GitHub Pages) para hospedar o `appcast.xml`. O GitHub Actions atualiza o `appcast.xml` automaticamente quando um release é criado.

### Configuração Inicial (Uma vez)

#### 1. Configurar GitHub Pages (opcional)

1. Acesse: https://github.com/cesar-carlos/plug_agente/settings/pages
2. Em "Source", selecione a branch `main`
3. Em "Folder", selecione `/ (root)`
4. A URL será: `https://cesar-carlos.github.io/plug_agente/appcast.xml`

#### 2. Verificar Permissões do GitHub Actions

1. Acesse: https://github.com/cesar-carlos/plug_agente/settings/actions
2. Em "Workflow permissions", selecione "Read and write permissions"
3. Marque "Allow GitHub Actions to create and approve pull requests"

#### 3. Configurar Variável de Ambiente

Adicione no arquivo `.env`:

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

**Alternativa (GitHub Pages):**

```env
AUTO_UPDATE_FEED_URL=https://cesar-carlos.github.io/plug_agente/appcast.xml
```

### Fluxo de Trabalho Automatizado

1. **Build do aplicativo:** `flutter build windows --release`
2. **Criar instalador:** `python installer/build_installer.py`
3. **Criar release no GitHub:** Consulte [release_guide.md](release_guide.md)
4. **GitHub Actions** executa automaticamente e atualiza o `appcast.xml`
5. Clientes recebem atualização na próxima verificação (a cada 1 hora) ou manualmente

### 4. Assinatura DSA (opcional, recomendado para produção)

O WinSparkle suporta verificação de assinatura DSA para garantir integridade dos updates. Para habilitar:

1. **Gerar chaves** (uma vez):
   ```bash
   dart run auto_updater:generate_keys
   ```
   Isso cria `dsa_priv.pem` e `dsa_pub.pem`.

2. **Adicionar chave pública ao app** – em `windows/runner/Runner.rc`:
   ```
   // WinSparkle
   DSAPub DSAPEM "../../dsa_pub.pem"
   ```

3. **Configurar secret no GitHub** – em Settings → Secrets → Actions:
   - Nome: `DSA_PRIVATE_KEY`
   - Valor: conteúdo completo do arquivo `dsa_priv.pem`

4. **Backup da chave privada** – guarde `dsa_priv.pem` em local seguro. Sem ela, usuários não poderão atualizar.

Com o secret configurado, o workflow `update-appcast` assina automaticamente cada release e adiciona `sparkle:dsaSignature` ao appcast.

### Estrutura do appcast.xml

O arquivo é mantido automaticamente pelo GitHub Actions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Plug Agente Updates</title>
    <link>https://github.com/cesar-carlos/plug_agente/releases</link>
    <item>
      <title>Version 1.0.0</title>
      <pubDate>Mon, 15 Jan 2024 10:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/cesar-carlos/plug_agente/releases/download/v1.0.0/PlugAgente-Setup-1.0.0.exe"
        sparkle:version="1.0.0"
        sparkle:os="windows"
        length="52428800"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

## Documentação Relacionada

- [testing_auto_update.md](testing_auto_update.md): Como testar o sistema de atualização
- [release_guide.md](release_guide.md): Como criar releases no GitHub
- [version_strategy.md](version_strategy.md): Estratégia de versionamento

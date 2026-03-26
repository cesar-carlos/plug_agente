# Configuração de Atualização Automática

Este documento explica como configurar e testar o sistema de atualização automática do Plug Agente.

> **Nota**: Para instruções de como testar o auto-update, consulte [testing_auto_update.md](testing_auto_update.md).
> **Nota**: Para instruções de como criar releases, consulte [release_guide.md](release_guide.md).

## Visão Geral

O aplicativo lê um feed **Sparkle** (RSS/XML) por **HTTPS**, compara a versão remota com a instalada e, se houver atualização, **abre o URL do instalador no navegador** padrão. Não há assinatura DSA/WinSparkle nem chaves no repositório ou no executável.

**Modelo de confiança:** TLS + URLs em hosts GitHub permitidos (`github.com`, `*.githubusercontent.com`, etc.).

O auto-update só é ativado quando `AUTO_UPDATE_FEED_URL` está configurado e aponta para um feed Sparkle (URL terminando em `.xml`).

Ordem de resolução da configuração do feed:

1. `--dart-define=AUTO_UPDATE_FEED_URL=...` no build (recomendado para release)
2. `.env` em runtime (fallback para desenvolvimento/testes)

Em modo degradado (Windows Server 2012/2016+), o auto-update não é suportado e a seção de atualizações exibe mensagem informativa.

Comportamento:

- checagem em background ao subir o app (registo em log se existir versão mais nova);
- polling em background a cada `AUTO_UPDATE_CHECK_INTERVAL_SECONDS` (mínimo 3600; omissão = 3600), além da checagem imediata no arranque;
- checagem manual nas definições: compara versões e, se houver update, abre o download no browser.

## Opção Recomendada: GitHub Releases + GitHub Raw

O projeto usa **GitHub Releases** para os executáveis e **GitHub Raw** (ou GitHub Pages) para o `appcast.xml`. O GitHub Actions atualiza o `appcast.xml` em cada release publicado (sem assinatura DSA).

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

#### 3. Configurar URL do feed (build/runtime)

**Opção recomendada (release):** usar `--dart-define` no build:

```bash
flutter build windows --release --dart-define=AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
```

> Se usar `python installer/build_installer.py`, o script injeta automaticamente esse `--dart-define` com base no `.env`.

**Fallback local (dev/teste):** adicionar no arquivo `.env`:

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
4. **GitHub Actions** executa automaticamente e atualiza o `appcast.xml` (sem `sparkle:dsaSignature`)
5. Clientes recebem indicação de atualização na verificação manual ou veem log em background

### Estrutura do appcast.xml

O arquivo é mantido automaticamente pelo GitHub Actions. Exemplo de `enclosure` (sem assinatura):

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

## Segurança

- Use **HTTPS** para o appcast e para o URL do instalador.
- Não há verificação criptográfica do binário no cliente; mitigue com origem confiável (GitHub) e revisão de releases.

## Documentação Relacionada

- [testing_auto_update.md](testing_auto_update.md): Como testar o sistema de atualização
- [release_guide.md](release_guide.md): Como criar releases no GitHub
- [version_strategy.md](version_strategy.md): Estratégia de versionamento

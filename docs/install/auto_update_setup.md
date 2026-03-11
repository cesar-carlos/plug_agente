# Configuração de Atualização Automática

Este documento explica como configurar e testar o sistema de atualização automática do Plug Agente.

> **Nota**: Para instruções de como testar o auto-update, consulte [testing_auto_update.md](testing_auto_update.md).
> **Nota**: Para instruções de como criar releases, consulte [release_guide.md](release_guide.md).

## Visão Geral

O sistema de atualização automática permite que o aplicativo verifique e instale atualizações automaticamente. Utiliza o pacote `auto_updater` (WinSparkle no Windows) com feed no formato Sparkle.

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
- [VERSION_STRATEGY.md](VERSION_STRATEGY.md): Estratégia de versionamento

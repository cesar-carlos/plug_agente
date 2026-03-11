# Guia de Teste - Sistema de Auto-Atualização

Este guia explica como testar o sistema de atualização automática do Plug Agente.

## Pré-requisitos

1. **Arquivo `.env` configurado** na raiz do projeto:

   ```env
   AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
   ```

2. **GitHub Pages configurado** (opcional): https://github.com/cesar-carlos/plug_agente/settings/pages

## Como Testar

### Método 1: Teste Manual na Interface

1. Execute: `flutter run -d windows`
2. Acesse **Configurações** > **Atualizações**
3. Clique em **"Verificar Atualizações"**
4. Se houver atualização disponível, uma janela será exibida

### Método 2: Teste com Versão de Desenvolvimento

1. Atualize a versão no `pubspec.yaml` (ex.: `1.0.1+2`)
2. Build: `flutter build windows --release`
3. Crie o instalador: `python installer/build_installer.py`
4. Crie um novo release no GitHub com tag `v1.0.1`
5. Faça upload do instalador `PlugAgente-Setup-1.0.1.exe`
6. Marque como **"Set as the latest release"** (não Pre-release)
7. Aguarde o workflow atualizar o `appcast.xml`
8. Execute a versão antiga e verifique se a atualização é detectada

### Verificar appcast.xml

Acesse no navegador:

- GitHub Raw: https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml
- GitHub Pages: https://cesar-carlos.github.io/plug_agente/appcast.xml

## Problemas Comuns

### O workflow não executou

- O release foi criado como Pre-release → desmarque e publique novamente

### Erro "AUTO_UPDATE_FEED_URL não configurada"

- Crie `.env` na raiz com `AUTO_UPDATE_FEED_URL=...`

### appcast.xml está vazio

- Verifique se o arquivo `.exe` foi anexado ao release
- O nome deve terminar com `.exe`

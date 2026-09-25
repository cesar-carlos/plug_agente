# Guia de Instalação - Plug Agente

Este guia passo a passo ajuda a instalar o **Plug Agente** no Windows.

---

## Pré-requisitos

Antes de comecar, confira [requirements.md](requirements.md): Windows 10+ 64
bits, permissao de administrador, internet na primeira instalacao (Visual C++
Redistributable x64) e driver ODBC 64 bits do banco.

---

## Passo 1: Download do Instalador

1. Baixe o arquivo `PlugAgente-Setup-{versão}.exe` da [página de releases](https://github.com/cesar-carlos/plug_agente/releases)
2. Salve o arquivo em um local de fácil acesso (ex.: `Downloads`)

---

## Passo 2: Executar o Instalador

1. **Localize o arquivo** do instalador (ex.: `PlugAgente-Setup-1.8.6.exe`)
2. **Clique com o botão direito** no arquivo
3. Selecione **"Executar como administrador"**
4. Se aparecer o **Controle de Conta de Usuário (UAC)**, clique em **"Sim"**

---

## Passo 3: Assistente de Instalação

A tela de boas-vindas fica desligada. O assistente começa pela pasta de instalação.

### 3.1 Localização de Instalação

- O instalador sugere: `C:\Program Files\Plug Agente`
- Para instalar em outro local, clique em **"Procurar"** e escolha a pasta
- Clique em **"Avançar"**

### 3.2 Tarefas adicionais

O instalador mostra opções para:

- **Criar um atalho na área de trabalho**
- **Iniciar com o Windows**: o aplicativo inicia no login do usuário que instalou, na bandeja quando ela estiver operacional. Detalhes em **Inicialização com o Windows** em [requirements.md](requirements.md).

Se o Microsoft Visual C++ Redistributable x64 não estiver presente, o setup baixa e instala o runtime da Microsoft antes de copiar os arquivos. Sem internet essa etapa falha e a instalação é abortada.

Selecione as opções desejadas e clique em **"Avançar"**

### 3.3 Pronto para Instalar

- Revise as opções selecionadas
- Clique em **"Instalar"** para começar a instalação

### 3.4 Instalação Concluída

- Marque **"Executar Plug Agente"** se desejar iniciar o aplicativo agora
- Clique em **"Concluir"**

O instalador registra o protocolo `plugdb://` para abrir o agente a partir de links no Windows.

---

## Instalação Silenciosa

Para distribuição por TI, use os parâmetros padrão do Inno Setup:

```powershell
PlugAgente-Setup-{versão}.exe /VERYSILENT /NORESTART /LOG
```

O instalador requer administrador. Se o Visual C++ Redistributable x64 não
estiver instalado, o setup tenta baixá-lo e instalá-lo; sem internet a
instalação silenciosa falha.

Sem `/TASKS` ou `/MERGETASKS`, as tarefas **Criar um atalho na área de
trabalho** e **Iniciar com o Windows** ficam selecionadas. Para desmarcar,
use por exemplo `/MERGETASKS="!desktopicon,!startup"`.

---

## Passo 4: Monitor de Portas (Opcional)

Se você utilizar o **Monitor de Portas** (PlugPortMon) para impressão:

1. Execute `install_monitor.bat` como administrador a partir da raiz do
   repositório, depois de compilar `native\PlugPortMon` (o script espera
   `native\PlugPortMon\build\Release\PlugPortMon.dll`). O instalador do
   Plug Agente não distribui esse script nem a DLL.
2. Crie a impressora no Windows apontando para a porta `PlugPortMon`
   (o script imprime o passo a passo ao final)

---

## Desinstalação

### Método 1: Via Painel de Controle

1. Abra o **Painel de Controle**
2. Vá em **Programas e Recursos**
3. Encontre **"Plug Agente"**
4. Clique em **"Desinstalar"**
5. Siga as instruções na tela

### Método 2: Via Menu Iniciar

1. Abra o **Menu Iniciar**
2. Encontre **"Plug Agente"**
3. Clique com o botão direito
4. Selecione **"Desinstalar"**

### Monitor de Portas

Se instalou o PlugPortMon, remova/desative o monitor de portas antes de
desinstalar o aplicativo principal.

### O que é removido

- Arquivos do aplicativo
- Atalhos e ícones
- Cache de updates em `C:\ProgramData\PlugAgente\updates`
- Marker de auto-start `C:\ProgramData\PlugAgente\autostart-requested`
- Entrada **Iniciar com o Windows**: HKCU Run, entradas legadas em HKLM
  (64/32 bits), o overlay `StartupApproved` e o valor Run de cada perfil com
  sessão aberta (perfis deslogados podem manter uma entrada órfã inofensiva)
- Registro do protocolo `plugdb://`

**NÃO remove**: Logs e demais configurações (permanecem em `C:\ProgramData\PlugAgente\`)

---

## Problemas Comuns

### "Você precisa de permissões de administrador"

1. Feche o instalador
2. Clique com o botão direito no arquivo `.exe`
3. Selecione **"Executar como administrador"**

### "Não foi possível baixar o Microsoft Visual C++ Redistributable x64"

1. Confirme a conexão com a internet e o acesso a `https://aka.ms/vs/17/release/vc_redist.x64.exe`
2. Ou instale o runtime manualmente e rode o setup de novo
3. Execute o instalador como administrador

### "Aplicativo não inicia após instalação"

1. Verifique se o Microsoft Visual C++ Redistributable x64 está instalado
2. Verifique os logs em: `C:\ProgramData\PlugAgente\logs\`
3. Tente executar como administrador

### "Driver ODBC ou ferramenta do banco não foi encontrada"

1. Confirme se o driver ODBC está instalado em **Fontes de Dados ODBC (64 bits)**
2. Revise a seção **PATH e Ferramentas CLI** em [requirements.md](requirements.md)
3. Reabra o terminal ou a sessão do Windows após alterar o PATH

---

## Suporte

Se encontrar problemas:

1. Consulte [requirements.md](requirements.md)
2. Verifique os logs em: `C:\ProgramData\PlugAgente\logs\`
3. Abra uma issue no repositório com versão do Windows e mensagens de erro

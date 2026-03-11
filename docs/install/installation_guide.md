# Guia de Instalação - Plug Agente

Este guia passo a passo ajuda a instalar o **Plug Agente** no Windows.

---

## Pré-requisitos

Antes de começar, certifique-se de ter:

1. **Windows 10 ou superior** (64 bits)
2. **Permissões de Administrador** para instalação
3. **Conexão com a Internet** (para atualizações, se configurado)
4. **Espaço em disco** suficiente (mínimo 500 MB)

Compatibilidade de sistema:
- **Windows Server 2012 / 2012 R2**: não suportado
- **Windows Server 2016+**: compatibilidade condicional (homologar no ambiente)

Consulte [requirements.md](requirements.md) para requisitos detalhados.

---

## Passo 1: Download do Instalador

1. Baixe o arquivo `PlugAgente-Setup-{versão}.exe` da [página de releases](https://github.com/cesar-carlos/plug_agente/releases)
2. Salve o arquivo em um local de fácil acesso (ex.: `Downloads`)

---

## Passo 2: Executar o Instalador

1. **Localize o arquivo** do instalador (ex.: `PlugAgente-Setup-1.0.0.exe`)
2. **Clique com o botão direito** no arquivo
3. Selecione **"Executar como administrador"**
4. Se aparecer o **Controle de Conta de Usuário (UAC)**, clique em **"Sim"**

---

## Passo 3: Assistente de Instalação

### 3.1 Tela de Boas-vindas

- Clique em **"Avançar"** para continuar

### 3.2 Licença

- Leia os termos de licença
- Se concordar, marque **"Aceito o acordo"**
- Clique em **"Avançar"**

### 3.3 Localização de Instalação

- O instalador sugere: `C:\Program Files\Plug Agente`
- Para instalar em outro local, clique em **"Procurar"** e escolha a pasta
- Clique em **"Avançar"**

### 3.4 Componentes Adicionais

O instalador pode mostrar opções para:

- **Criar ícone na área de trabalho**: Marque se desejar um atalho na área de trabalho
- **Iniciar com o Windows**: Marque se desejar que o aplicativo inicie automaticamente

Selecione as opções desejadas e clique em **"Avançar"**

### 3.5 Pronto para Instalar

- Revise as opções selecionadas
- Clique em **"Instalar"** para começar a instalação

### 3.6 Instalação Concluída

- Marque **"Executar Plug Agente"** se desejar iniciar o aplicativo agora
- Clique em **"Concluir"**

---

## Passo 4: Monitor de Portas (Opcional)

Se você utilizar o **Monitor de Portas** (PlugPortMon) para impressão:

1. Execute o script `install_monitor.bat` como administrador (na pasta de instalação ou na raiz do projeto)
2. Siga as instruções em [path_setup.md](path_setup.md) se necessário
3. Crie a impressora no Windows apontando para a porta `PlugPortMon`

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

Se instalou o PlugPortMon, execute `docs\install\uninstall_monitor.bat` como administrador antes de desinstalar o aplicativo.

### O que é removido

- Arquivos do aplicativo
- Atalhos e ícones
- **NÃO remove**: Logs e configurações salvas (ficam em `C:\ProgramData\PlugAgente\`)

---

## Problemas Comuns

### "Você precisa de permissões de administrador"

1. Feche o instalador
2. Clique com o botão direito no arquivo `.exe`
3. Selecione **"Executar como administrador"**

### "Visual C++ Redistributables falhou ao instalar"

1. Baixe manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe
2. Execute como administrador
3. Tente instalar o Plug Agente novamente

### "Aplicativo não inicia após instalação"

1. Verifique se o Visual C++ Redistributables está instalado
2. Verifique os logs em: `C:\ProgramData\PlugAgente\logs\`
3. Tente executar como administrador

---

## Suporte

Se encontrar problemas:

1. Consulte [requirements.md](requirements.md)
2. Verifique os logs em: `C:\ProgramData\PlugAgente\logs\`
3. Abra uma issue no repositório com versão do Windows e mensagens de erro

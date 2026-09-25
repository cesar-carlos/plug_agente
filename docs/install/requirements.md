# Requisitos do Sistema

Requisitos para instalar e executar o Plug Agente pelo instalador Windows.

## Requisitos Mínimos

| Item                    | Especificação                    |
| ----------------------- | -------------------------------- |
| Sistema operacional     | Windows 10 ou superior, 64 bits  |
| Arquitetura             | x64                              |
| Memória RAM             | 4 GB                             |
| Espaço em disco         | 500 MB                           |
| Permissões              | Administrador para instalação    |
| Runtime                 | Microsoft Visual C++ Redistributable x64 |

O instalador verifica o Microsoft Visual C++ Redistributable x64. Se ele não
estiver presente, o setup baixa `vc_redist.x64.exe` da Microsoft e instala em
modo quieto. Sem HTTPS a instalação é abortada (também em `/VERYSILENT`).

URL usada pelo instalador:

```text
https://aka.ms/vs/17/release/vc_redist.x64.exe
```

## Compatibilidade de Plataforma

| Plataforma        | Versão                     | Status no instalador | Observações                                      |
| ----------------- | -------------------------- | -------------------- | ------------------------------------------------ |
| Windows cliente   | Windows 10 e Windows 11    | Suportado            | Modo completo                                    |
| Windows Server    | Server 2016 ou superior    | Suportado            | Pode executar em modo degradado                  |
| Windows cliente   | Windows 8 / 8.1 ou inferior | Não suportado        | Bloqueado pelo instalador                        |
| Windows Server    | Server 2012 / 2012 R2 ou inferior | Não suportado  | Bloqueado pelo instalador                        |

Em modo degradado, recursos de desktop podem ficar indisponíveis, como tray,
notificações locais e auto-update. O core do agente, ODBC, Socket.IO e
Playground SQL devem continuar funcionando quando o runtime permitir.

## Inicialização com o Windows

- Instalações novas com a task **Iniciar com o Windows** selecionada gravam
  HKCU Run para o usuário interativo via `runasoriginaluser` (`[Run]` +
  `reg add`) e deixam o marker `{commonappdata}\PlugAgente\autostart-requested`.
  No primeiro lançamento (manual ou `--autostart`) o app registra HKCU para o
  usuário logado e limpa o marker; se a limpeza falhar, tenta de novo no
  próximo boot.
- Updates silenciosos passam `/MERGETASKS="!desktopicon,!startup"` e **não**
  re-solicitam auto-start.
- Login com `--autostart` permanece na bandeja (tray) quando o tray está
  operacional. Se a inicialização da bandeja falhar ou o ambiente não a
  suportar, o app revela a janela como fallback seguro e preserva as
  preferências de bandeja para a próxima sessão. Não há toggle de "iniciar
  minimizado" em Configurações; lançamentos manuais abrem a janela.
- Se o usuário desligar o app em **Gerenciador de Tarefas > Aplicativos de
  inicialização**, o agente persiste `startWithWindows=false` e **não**
  repara a entrada sozinho. Overlay `StartupApproved` ímpar (ou
  inclassificável) conta como escolha do usuário.
- Um toggle explícito em Configurações apaga o marker pendente do instalador,
  para ele não religar o auto-start no próximo boot.
- Desligar o toggle apaga primeiro entradas HKLM (pode pedir UAC). Cancelar
  ou deixar o prompt sem resposta (2 minutos) deixa o auto-start intacto.
- Após pelo menos 60 s em execução (Release), um crash ou travamento nativo
  relança o app na bandeja (`--autostart`). Update e reboot não usam esse
  caminho.
- Falha de bootstrap no `--autostart` revela a janela e o diálogo de erro
  (não deixa o processo invisível com o mutex preso).
- Configurações > copiar diagnóstico inclui preferência, último `--autostart`,
  marker do instalador, resultado do boot e bytes do `StartupApproved`.
- Upgrades de instalações antigas podem deixar uma entrada legada em **HKLM** ou
  **WOW6432Node**; o app oferece reparo nas preferências e pode solicitar UAC
  **uma vez** para remover a duplicata.
- A desinstalação remove essas entradas; veja **O que é removido** em
  [installation_guide.md](installation_guide.md).

## ODBC

O Plug Agente usa ODBC para conectar aos bancos locais. Instale o driver ODBC
64 bits do banco que será usado, como SQL Server ou SQL Anywhere.

Para verificar drivers instalados:

1. Abra **Ferramentas Administrativas** > **Fontes de Dados ODBC (64 bits)**.
2. Na aba **Drivers**, confirme se o driver esperado está listado.

## PATH e Ferramentas CLI

Normalmente não é necessário alterar `PATH`. Faça isso apenas se o driver ou
uma ferramenta de banco precisar ser chamada por linha de comando, como
`sqlcmd`.

## Rede

- HTTPS para `aka.ms` na primeira instalação se o Visual C++ Redistributable
  x64 ainda não estiver no Windows.
- Acesso ao hub remoto quando Socket.IO estiver configurado.
- Acesso ao feed oficial se o auto-update estiver habilitado.
- Regras de proxy/firewall devem permitir HTTPS para GitHub Releases e GitHub
  Pages quando updates automáticos forem usados.

## Verificação Pós-Instalação

1. Execute o Plug Agente pelo menu Iniciar.
2. Acesse **Configurações** e confira a versão exibida.
3. Teste uma conexão ODBC.
4. Se houver erro, verifique logs da aplicação em
   `C:\ProgramData\PlugAgente\logs\`.
5. Para problemas do instalador, consulte o log gerado pelo Inno Setup.

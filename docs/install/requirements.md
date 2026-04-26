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

O instalador verifica o Microsoft Visual C++ Redistributable x64 e mostra um
aviso quando ele não é detectado. Em instalações silenciosas, o aviso é gravado
no log do instalador e a instalação continua.

Download manual:

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

- Acesso ao hub remoto quando Socket.IO estiver configurado.
- Acesso ao feed oficial se o auto-update estiver habilitado.
- Regras de proxy/firewall devem permitir HTTPS para GitHub Releases e GitHub
  Raw quando updates automáticos forem usados.

## Verificação Pós-Instalação

1. Execute o Plug Agente pelo menu Iniciar.
2. Acesse **Configurações** e confira a versão exibida.
3. Teste uma conexão ODBC.
4. Se houver erro, verifique logs da aplicação em
   `C:\ProgramData\PlugAgente\logs\`.
5. Para problemas do instalador, consulte o log gerado pelo Inno Setup.

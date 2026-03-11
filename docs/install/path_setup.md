# Configuração do PATH - Plug Agente

O Plug Agente utiliza **ODBC** para conexão com bancos de dados. Em geral, não é necessário configurar variáveis de ambiente PATH para o aplicativo funcionar.

## Quando Configurar o PATH

Configure o PATH apenas se:

- O driver ODBC não for encontrado automaticamente
- Você precisar usar ferramentas de linha de comando relacionadas ao banco (ex.: `sqlcmd` para SQL Server)

## Drivers ODBC

Os drivers ODBC são registrados no Windows e o Plug Agente os localiza automaticamente. Para verificar drivers instalados:

1. Abra **Ferramentas Administrativas** > **Fontes de Dados ODBC (64 bits)**
2. Na aba **Drivers**, verifique se o driver do seu banco está listado

## Exemplo: SQL Server

Se usar SQL Server e precisar do `sqlcmd`:

1. Instale o [SQL Server Command Line Utilities](https://go.microsoft.com/fwlink/?linkid=2230791)
2. Adicione o caminho de instalação (ex.: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn`) ao PATH do sistema

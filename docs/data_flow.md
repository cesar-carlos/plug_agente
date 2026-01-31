# Fluxo de Dados no Plug Agente

Este diagrama explica como os dados fluem entre as camadas da arquitetura limpa do projeto.

## Visão Geral

```mermaid
flowchart TD
  subgraph Subgraph
    direction LR

    Hub[Hub_SocketIO] --> Client[ClientApp_Windows]

    subgraph AgentRuntime[AgentRuntime]
      Transport[SocketClient_Infrastructure]
      Gateway[OdbcDatabaseGateway_Infrastructure]
        Normalizer[Normalizer_Application]
        Compressor[GzipCompressor_Infrastructure]
        SQLiteRepo[AgentConfigRepository_Drift]

    Hub --> SocketClient
    SocketClient --> RequestHandler[HandleQueryRequest_UseCase]
    RequestHandler --> DatabaseGateway
    DatabaseGateway --> Normalizer
    Normalizer --> Compressor
    Compressor --> SocketClient
    SocketClient --> ResponseHub

    AgentRuntime --> SQLiteRepo
    SQLiteRepo --> ConfigProvider
    ConfigProvider --> UI
    UI --> User
  end

    style Hub fill:#f9f9f9
    style Transport fill:#90caf9
    style Gateway fill:#91ccf2
    style Normalizer fill:#81c784
    style Compressor fill:#82b368
    style SQLiteRepo fill:#f7e7e7
    classDef default fill:#e1f5fe
```

## Componentes Principais

### 1. Client App (Windows Tray)

- Ponto de entrada e saída para o usuário
- Gerencia ciclo de vida do aplicativo
- Exibe menu na bandeja do sistema

### 2. Agent Runtime

- Orquestra e processa as requisições
- Comunica-se com o Hub via Socket.IO
- Gerencia estado da conexão

### 3. Camada de Transporte

- Implementa comunicação Socket.IO
- Gerencia conexões e reconexões automáticas
- Serializa e desserializa mensagens usando Envelope V1

### 4. Camada de Gateway

- Interface para acesso a bancos de dados
- Executa consultas SQL com parâmetros
- Testa conectividade com o banco

### 5. Camada de Normalização

- Padroniza nomes de colunas
- Valida consultas SQL antes de executar
- Converte resultados para formato padrão

### 6. Camada de Compressão

- Comprime dados usando gzip
- Converte para base64 para transmissão
- Reduz tamanho dos pacotes

### 7. Repositório SQLite

- Armazena configurações do agente
- ORM usando Drift
- Acesso seguro a dados locais

## Fluxo de Operação

### 1. Inicialização

1. **ClientApp** inicia e carrega dependências
2. Verifica configurações salvas no SQLite
3. Inicializa Socket.IO e conecta ao Hub
4. Registra o agente no servidor

### 2. Ciclo de Operação

1. **Hub** envia requisição de consulta (`QueryRequest`)
2. **SocketClient** recebe e desserializa requisição
3. **HandleQueryRequest** valida e executa consulta:
   a. Usa **DatabaseGateway** para executar SQL
   b. Usa **Normalizer** para padronizar resultado
   c. Usa **Compressor** para compactar dados
4. **SocketClient** envia resposta compactada (`QueryResponse`)

### 3. Gerenciamento de Estado

1. **ConnectionProvider** monitora estado das conexões
2. **ConfigProvider** gerencia estado das configurações
3. UI exibe indicadores visuais e permite interação

## Tecnologias Utilizadas

- **Socket.IO**: Comunicação bidirecional em tempo real
- **ODBC**: Acesso nativo a bancos de dados relacionais
- **SQLite**: Armazenamento local leve e portátil
- **Fluent UI**: Interface moderna para Windows
- **Drift**: ORM eficiente com código gerado
- **Gzip**: Compressão padrão da indústria

## Considerações de Performance

- **Lazy Loading**: Configurações carregadas apenas quando necessárias
- **Connection Pooling**: Reutilização de conexões com o banco
- **Batch Processing**: Processamento de múltiplas consultas
- **Memory Efficient**: Estruturas de dados otimizadas para minimizar uso de memória

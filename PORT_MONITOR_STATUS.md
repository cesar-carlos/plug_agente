# Relatório de Implementação: Port Monitor

## 1. Visão Geral

Atualmente, o projeto possui a **interface de usuário (UI)** para o Monitor de Portas e um **serviço de infraestrutura** em Dart, mas toda a lógica funcional é **simulada**. Não existe comunicação real com o Spooler de Impressão do Windows nem implementação de baixo nível (C++) para interceptar os dados de impressão.

## 2. Estado Atual da Implementação

### A. Camada Dart/Flutter (Existente)
*   **UI (`PortMonitorPage`)**: Tela completa com visualização de status (Conectado/Parado) e log de atividades.
*   **Serviço (`PortMonitorService`)**:
    *   A classe existe e gerencia o estado da aplicação.
    *   **Simulação**: Utiliza um `Timer` para gerar logs falsos ("Received print job data").
    *   **Comunicação**: Nenhuma implementação de Named Pipes ou Sockets. A string `\\.\pipe\PlugAgentPipe` é apenas exibida como texto estático na UI.

### B. Camada Windows/C++ (Inexistente)
*   **Port Monitor DLL**: Não existe nenhum projeto ou arquivo fonte C++ configurado para atuar como um Monitor de Porta de Impressora. O código atual em `windows/runner` é apenas o shell padrão do Flutter.
*   **Inter-Process Communication (IPC)**: Não há código para criar ou consumir Named Pipes.

---

## 3. O Que Falta Implementar (Roteiro Técnico)

Para tornar o Port Monitor funcional, a implementação deve ser dividida em dois componentes principais: uma DLL Nativa (Backend) e o Cliente Dart (Frontend).

### Fase 1: C++ Port Monitor DLL (Crítico)
O Windows Spooler não pode carregar um executável Flutter diretamente. Ele precisa de uma DLL específica que exporte funções definidas pela Microsoft.

*   **Criar Projeto DLL separado**: É necessário criar um projeto C++ (Visual Studio ou CMake) para gerar uma DLL (ex: `PlugPortMon.dll`).
*   **Implementar Interface do Monitor**:
    *   `InitializePrintMonitor2`: Inicialização do monitor.
    *   `OpenPort`: Chamado quando o Spooler abre a porta.
    *   `StartDocPort`: Chamado no início de um trabalho de impressão.
    *   `WritePort`: **Ponto Crítico**. É aqui que os dados (bytes) da impressão chegam. O código deve pegar esses dados e escrevê-los no Named Pipe.
    *   `EndDocPort`: Fim do trabalho.
    *   `ClosePort`: Fechamento da porta.
*   **Servidor Named Pipe**: Dentro da DLL, implementar a criação/conexão a um Named Pipe (ex: `\\.\pipe\PlugAgentPipe`) para enviar os dados recebidos no `WritePort` para o Flutter.

### Fase 2: Integração Dart (Cliente Named Pipe)
Atualizar o `PortMonitorService` para ouvir o Named Pipe real.

*   **Remover Simulação**: Apagar o `Timer` e lógica de dados falsos.
*   **Implementar Leitor de Pipe**:
    *   Opção A (Simples): Usar `File('\\\\.\\pipe\\PlugAgentPipe')` do `dart:io` para leitura (se o pipe permitir modo de arquivo).
    *   Opção B (Robusta - Recomendada): Usar o pacote `win32` com FFI para chamar `CreateFile` e `ReadFile` de forma assíncrona, garantindo que a UI não trave enquanto espera dados.
*   **Parser de Dados (Opcional)**: Se os dados forem comandos ESC/POS ou texto puro, implementar um parser para converter os bytes recebidos em texto legível para o log.

### Fase 3: Instalação e Registro (Sistema)
O Windows não "descobre" monitores de porta automaticamente.

*   **Registro no Registry**: A DLL precisa ser registrada em `HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors`.
*   **Reinício do Spooler**: O serviço de Spooler precisa ser reiniciado para carregar a nova DLL.
*   **Criação da Impressora**: O usuário precisará criar uma impressora no Windows e apontá-la para a porta gerenciada por este monitor (ex: `PLUG001:`).

## 4. Resumo da Arquitetura Alvo

```mermaid
graph TD
    A[Aplicação (Word/Notepad)] -->|Imprimir| B[Windows Spooler]
    B -->|Carrega| C[PlugPortMon.dll (C++)]
    C -->|WritePort recebe Bytes| D{Tem Conexão?}
    D -- Sim -->|Envia Bytes via Pipe| E[Named Pipe server]
    D -- Não -->|Buffer/Descarta| F[Log Error]
    E -->|IPC| G[Flutter App (Dart)]
    G -->|PortMonitorService| H[UI Logs]
```

## Próximos Passos Imediatos Sugeridos:
1.  **Implementar a DLL C++**: Começar criando o esqueleto da DLL com as funções exportadas básicas.
2.  **Configurar o Named Pipe Server na DLL**: Testar comunicação com um script simples antes de integrar no Spooler.

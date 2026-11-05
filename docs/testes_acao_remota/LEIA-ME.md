# Teste manual de ação remota

Confere, a partir desta máquina, se o Hub aceitou `agent.action.run` de uma ação salva no agente e se o processo terminou com sucesso. O script no agente devolve o marcador e a identidade da máquina: nome, usuário, Windows, arquitetura, pid, hora local e caminho do arquivo. A chamada envia o texto de `echo` na entrada padrão e o script devolve a mesma linha em `PLUG_REMOTE_ECHO`. O chamador imprime esse stdout e confirma que o valor enviado voltou.

Isto não liga produção e não envia comando livre. A entrada vai em `io.initial_input_base64`, com a entrada encerrada na mesma chamada.

## No agente

1. Copie `acao_no_agente.ps1` para um caminho fixo da máquina do agente, por exemplo `C:\PlugAcaoRemota\acao_no_agente.ps1`.
2. Crie uma ação do tipo **Script**.
3. Caminho do script: o arquivo copiado. Deixe o interpretador vazio. O agente usa `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`.
4. Deixe a captura de stdout ligada e ligue **Permitir entrada e saída remota fiel**.
5. Ligue **Execução remota**, crie um gatilho remoto habilitado, salve e aprove.
6. Deixe **Ad-hoc remoto** desligado. Se a ação já tiver esse chip, a preferência de ad-hoc também precisa estar ligada.
7. Em Preferências, **Ações remotas e entrada/saída**, ligue **Permitir ações remotas** e **Permitir entrada/saída de processos**. Saia pela bandeja e abra o agente de novo.
8. Anote o `action_id`. Se houver mais de um gatilho remoto, anote também o `trigger_id`.

## Nesta máquina

1. Copie `config.example.json` para `config.local.json` nesta pasta.
2. Preencha a URL do Hub, o `agentId`, o `clientToken` da credencial local, o `actionId` e o `echo`.
3. Informe `accessToken` ou o e-mail e a senha do Client que já tem acesso a esse agente.
4. Na credencial local, preencha **Agent ID** com o identificador deste agente. O exemplo `agent-01` não vale. Em **Payload JSON**, clique em **Incluir escopos de entrada fiel** para adicionar os quatro escopos do exemplo. `action_ids` é opcional e, quando presente, limita o token a essas ações. Salvar o payload rotaciona o token: copie o valor novo para `clientToken`. O `echo` é uma linha só. O exemplo usa `eco-remoto-ok`.

```json
{
  "agent_actions": {
    "scopes": [
      "agent_actions.run",
      "agent_actions.validate_run",
      "agent_actions.read_execution",
      "agent_actions.io"
    ],
    "action_ids": [
      "cole-aqui-o-action-id"
    ]
  }
}
```

Para executar o teste completo, rode o comando abaixo **sem `-SomenteValidar`**. Ele chama `agent.action.run` e confere se o agente devolveu o eco enviado.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\testes_acao_remota\chamar_daqui.ps1
```

Use `-SomenteValidar` para validar a ação sem iniciar o processo. Essa opção chama `agent.action.validateRun` e exige `agent_actions.validate_run` e `agent_actions.io`, ambos incluídos pelo botão. Se a credencial foi salva antes da inclusão de `agent_actions.validate_run`, edite-a, clique novamente no botão, salve e copie o novo token para `clientToken`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\testes_acao_remota\chamar_daqui.ps1 -SomenteValidar
```

`config.local.json` e `ultima_chamada.json` ficam de fora do Git. `ultima_chamada.json` guarda a chave de idempotência e o `execution_id` para consultar de novo se a resposta se perder. Não rode o script outra vez com outra chave nesse caso.

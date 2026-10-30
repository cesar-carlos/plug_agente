import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

/** Runs only inside the isolated hub companion with its own authenticated Client. */
export async function verifyReferenceClient(options: {
  requireServer: NodeRequire;
  hubUrl: string;
  agentId: string;
  accessToken: string;
  credential: string;
  foreignCredential?: string;
  thirdCredential?: string;
  actionId: string;
  progress(stage: string): void;
}): Promise<void> {
  const { ActionIoReferenceClient } = options.requireServer(
    "./docs/snippets/action_io_reference_client",
  );
  const { createRestActionIoTransport } = options.requireServer(
    "./docs/snippets/action_io_rest_transport",
  );
  const { createSocketActionIoTransport } = options.requireServer(
    "./docs/snippets/action_io_socket_transport",
  );
  const { io } = options.requireServer("socket.io-client");
  for (const mode of ["rest", "socket", "relay"]) {
    options.progress(`${mode}:connect`);
    let socket: ReturnType<typeof io> | undefined;
    let dispose: (() => void) | undefined;
    let abortController = new AbortController();
    let requestBudgetMs = 30000;
    try {
      let transport: ReturnType<typeof createRestActionIoTransport>;
      async function connect(): Promise<void> {
        dispose?.();
        socket?.disconnect();
        abortController = new AbortController();
        if (mode === "rest") {
          transport = createRestActionIoTransport({
            endpoint: `${options.hubUrl}/api/v1/agents/commands`,
            agentId: options.agentId,
            bearerToken: () => options.accessToken,
            signal: abortController.signal,
            fetch: (url: string, init: RequestInit) =>
              fetch(url, {
                ...init,
                body: JSON.stringify({
                  ...JSON.parse(init.body as string),
                  timeoutMs: requestBudgetMs,
                }),
              }),
          });
        } else {
          socket = io(`${options.hubUrl}/consumers`, {
            transports: ["websocket"],
            auth: { token: options.accessToken },
            autoConnect: false,
            reconnection: false,
            forceNew: true,
            retries: 2,
            ackTimeout: 50,
          });
          await new Promise<void>((resolve, reject) => {
            const timer = setTimeout(
              () => reject(new Error("Reference connection timeout")),
              10000,
            );
            socket.once("connection:ready", () => {
              clearTimeout(timer);
              resolve();
            });
            socket.once("connect_error", () => {
              clearTimeout(timer);
              reject(new Error("Reference connection refused"));
            });
            socket.connect();
          });
          let conversationId: string | undefined;
          if (mode === "relay") {
            conversationId = await new Promise<string>((resolve, reject) => {
              const timer = setTimeout(
                () => reject(new Error("Reference conversation timeout")),
                10000,
              );
              socket.once(
                "relay:conversation.started",
                (body: Record<string, unknown>) => {
                  clearTimeout(timer);
                  if (
                    body.success !== true ||
                    body.agentId !== options.agentId ||
                    typeof body.conversationId !== "string"
                  ) {
                    reject(new Error("Reference conversation refused"));
                    return;
                  }
                  resolve(body.conversationId);
                },
              );
              socket.volatile.emit("relay:conversation.start", {
                agentId: options.agentId,
              });
            });
          }
          transport = createSocketActionIoTransport({
            socket: {
              get connected() {
                return socket.connected;
              },
              get io() {
                return socket.io;
              },
              on: socket.on.bind(socket),
              off: socket.off.bind(socket),
              emit: socket.emit.bind(socket),
              volatile: {
                emit: (event: string, body: Record<string, unknown>) =>
                  socket.volatile.emit(event, {
                    ...body,
                    timeoutMs: requestBudgetMs,
                  }),
              },
            },
            agentId: options.agentId,
            ...(conversationId === undefined
              ? {}
              : { relayConversationId: conversationId }),
          });
          dispose = () => transport.dispose();
        }
      }
      await connect();
      let client: InstanceType<typeof ActionIoReferenceClient> =
        new ActionIoReferenceClient(transport, () => options.credential);
      const key = `reference-${mode}-${randomUUID()}`;
      const initial = Uint8Array.from(
        { length: 65536 },
        (_, index) => index & 255,
      );
      const interactive = Uint8Array.from(
        { length: 65536 },
        (_, index) => 255 - (index & 255),
      );
      const suffix = Uint8Array.from([0, 255, 13, 10, 26, 128, 1]);
      options.progress(`${mode}:run`);
      const run = await client.run(options.actionId, key, {
        initial,
        closeInput: false,
      });
      const executionId = run.execution_id as string;
      assert.equal(typeof executionId, "string");
      if (options.foreignCredential !== undefined) {
        options.progress(`${mode}:foreign-client`);
        const { isValidActionIoResponse } = options.requireServer(
          "./src/shared/validators/action_io_result",
        );
        const { captureActionIoExpectation } = options.requireServer(
          "./src/shared/validators/action_io_response_expectation",
        );
        const attempts: Array<[string, Record<string, unknown>]> = [
          ["agent.action.getExecution", {}],
          [
            "agent.action.readIo",
            { after_sequence: 0, max_bytes: 65536, wait_ms: 0 },
          ],
          ["agent.action.getInputStatus", { message_id: "foreign-status" }],
          [
            "agent.action.sendInput",
            { message_id: "foreign-input", sequence: 1, data_base64: "AQ==" },
          ],
          [
            "agent.action.closeInput",
            { message_id: "foreign-close", sequence: 1 },
          ],
          ["agent.action.cancel", {}],
        ];
        for (const [method, extra] of attempts) {
          options.progress(`${mode}:foreign-client:${method}`);
          const command: Record<string, unknown> = {
            jsonrpc: "2.0",
            id: randomUUID(),
            method,
            params: {
              execution_id: executionId,
              client_token: options.foreignCredential,
              ...extra,
            },
          };
          const response: { error?: { data?: { failure_code?: string } } } =
            await transport(command);
          assert.equal(
            isValidActionIoResponse(
              method,
              response,
              captureActionIoExpectation(command),
            ),
            true,
          );
          assert.equal(
            response.error?.data?.failure_code,
            "ACTION_IO_UNAUTHORIZED",
          );
        }
        const foreignClient = new ActionIoReferenceClient(
          transport,
          () => options.foreignCredential!,
        );
        options.progress(`${mode}:foreign-client:findExecution`);
        const foreignLookup = await foreignClient.findExecution(
          options.actionId,
          key,
        );
        assert.equal(foreignLookup.found, false);
      }
      options.progress(`${mode}:input`);
      assert.equal(
        (await client.sendInput(executionId, "interactive", 1, interactive))
          .state,
        "accepted",
      );
      assert.equal(
        (await client.sendInput(executionId, "suffix", 2, suffix)).state,
        "accepted",
      );
      options.progress(`${mode}:close`);
      await client.closeInput(executionId, "close", 3);
      const streams: Record<string, Buffer[]> = { stdout: [], stderr: [] };
      let cursor = 0;
      let completed = false;
      let pages = 0;
      let reconnected = false;
      const deadline = Date.now() + 30000;
      while (!completed && Date.now() < deadline) {
        options.progress(`${mode}:read`);
        const page = await client.readIo(executionId, cursor, 1000);
        pages++;
        for (const event of page.events as Array<Record<string, unknown>>) {
          if (event.type === "output")
            streams[event.stream as string]!.push(
              Buffer.from(event.data_base64 as string, "base64"),
            );
          if (event.type === "completed") {
            assert.equal(event.output_complete, true);
            completed = true;
          }
        }
        cursor = page.next_sequence as number;
        if (completed) {
          assert.equal(page.terminal, true);
          assert.equal(page.output_complete, true);
        }
        if (cursor > 0 && !completed && !reconnected && mode !== "rest") {
          options.progress(`${mode}:reconnect`);
          await connect();
          client = new ActionIoReferenceClient(
            transport,
            () => options.credential,
          );
          assert.equal(
            (await client.findExecution(options.actionId, key)).execution_id,
            executionId,
          );
          reconnected = true;
        }
      }
      assert.equal(completed, true);
      assert.ok(pages > 1);
      if (mode !== "rest") assert.equal(reconnected, true);
      const expected = Buffer.concat([initial, interactive, suffix]);
      assert.deepEqual(Buffer.concat(streams.stdout!), expected);
      assert.deepEqual(Buffer.concat(streams.stderr!), expected);
      options.progress(`${mode}:receipt`);
      const receipt = await client.getInputStatus(executionId, "interactive");
      assert.equal(receipt.state, "written");
      assert.equal(receipt.confirmed_bytes, interactive.length);
      options.progress(`${mode}:reconcile`);
      assert.equal(
        (await client.sendInput(executionId, "interactive", 1, interactive))
          .state,
        "written",
      );
      assert.equal(
        (await client.findExecution(options.actionId, key)).execution_id,
        executionId,
      );
      const duplicate = await client.run(options.actionId, key, {
        initial,
        closeInput: false,
      });
      assert.equal(duplicate.execution_id, executionId);
      assert.equal(duplicate.status, "succeeded");
      if (options.foreignCredential !== undefined) {
        const foreignClient = new ActionIoReferenceClient(
          transport,
          () => options.foreignCredential!,
        );
        const { isValidActionIoResponse } = options.requireServer(
          "./src/shared/validators/action_io_result",
        );
        const { captureActionIoExpectation } = options.requireServer(
          "./src/shared/validators/action_io_response_expectation",
        );
        options.progress(`${mode}:foreign-client:scoped-key`);
        const validationCommand: Record<string, unknown> = {
          jsonrpc: "2.0",
          id: randomUUID(),
          method: "agent.action.validateRun",
          params: {
            action_id: options.actionId,
            idempotency_key: key,
            client_token: options.foreignCredential,
            io: {
              version: 1,
              mode: "faithful",
              close_input: true,
              initial_input_base64: Buffer.from(suffix).toString("base64"),
            },
          },
        };
        const validation: { result?: Record<string, unknown> } =
          await transport(validationCommand);
        assert.equal(
          isValidActionIoResponse(
            "agent.action.validateRun",
            validation,
            captureActionIoExpectation(validationCommand),
          ),
          true,
        );
        assert.equal(validation.result?.would_replay_existing_execution, false);
        assert.equal(
          (await foreignClient.findExecution(options.actionId, key)).found,
          false,
        );
        options.progress(`${mode}:foreign-client:concurrent-run`);
        const [foreignRun, concurrentRun] = await Promise.all([
          foreignClient.run(options.actionId, key, {
            initial: suffix,
            closeInput: true,
          }),
          foreignClient.run(options.actionId, key, {
            initial: suffix,
            closeInput: true,
          }),
        ]);
        const foreignId = foreignRun.execution_id as string;
        assert.equal(concurrentRun.execution_id, foreignId);
        assert.notEqual(foreignId, executionId);
        assert.equal(
          (await foreignClient.findExecution(options.actionId, key))
            .execution_id,
          foreignId,
        );
        assert.equal(
          (await client.findExecution(options.actionId, key)).execution_id,
          executionId,
        );
        const foreignStreams: Record<string, Buffer[]> = {
          stdout: [],
          stderr: [],
        };
        let foreignCursor = 0;
        let foreignComplete = false;
        const foreignDeadline = Date.now() + 15000;
        while (!foreignComplete && Date.now() < foreignDeadline) {
          const page = await foreignClient.readIo(
            foreignId,
            foreignCursor,
            1000,
          );
          for (const event of page.events as Array<Record<string, unknown>>) {
            if (event.type === "output")
              foreignStreams[event.stream as string].push(
                Buffer.from(event.data_base64 as string, "base64"),
              );
            if (event.type === "completed") foreignComplete = true;
          }
          foreignCursor = page.next_sequence as number;
        }
        assert.equal(foreignComplete, true);
        for (const stream of ["stdout", "stderr"])
          assert.deepEqual(
            Buffer.concat(foreignStreams[stream]),
            Buffer.from(suffix),
          );
        const foreignReplay = await foreignClient.run(options.actionId, key, {
          initial: suffix,
          closeInput: true,
        });
        assert.equal(foreignReplay.execution_id, foreignId);
        assert.equal(foreignReplay.status, "succeeded");
        options.progress(`${mode}:foreign-client:terminal-validation`);
        const terminalValidationCommand = {
          ...validationCommand,
          id: randomUUID(),
        };
        const terminalValidation: { result?: Record<string, unknown> } =
          await transport(terminalValidationCommand);
        assert.equal(
          isValidActionIoResponse(
            "agent.action.validateRun",
            terminalValidation,
            captureActionIoExpectation(terminalValidationCommand),
          ),
          true,
        );
        assert.equal(
          terminalValidation.result?.would_replay_existing_execution,
          true,
        );
        assert.equal(
          terminalValidation.result?.existing_execution_id,
          foreignId,
        );
        options.progress(`${mode}:foreign-client:conflict`);
        const conflictingCommand: Record<string, unknown> = {
          jsonrpc: "2.0",
          id: randomUUID(),
          method: "agent.action.run",
          params: {
            action_id: options.actionId,
            idempotency_key: key,
            client_token: options.foreignCredential,
            io: {
              version: 1,
              mode: "faithful",
              close_input: true,
              initial_input_base64: "Yw==",
            },
          },
        };
        const conflict: {
          error?: { code?: number; data?: { failure_code?: string } };
        } = await transport(conflictingCommand);
        assert.equal(
          isValidActionIoResponse(
            "agent.action.run",
            conflict,
            captureActionIoExpectation(conflictingCommand),
          ),
          true,
        );
        assert.equal(conflict.error?.code, -32602);
        assert.equal(
          conflict.error?.data?.failure_code,
          "ACTION_INPUT_CONFLICT",
        );
        assert.equal(
          (await foreignClient.findExecution(options.actionId, key))
            .execution_id,
          foreignId,
        );
      }
      options.progress(`${mode}:abandoned-read`);
      const idleKey = `reference-idle-${mode}-${randomUUID()}`;
      const idle = await client.run(options.actionId, idleKey, {
        closeInput: false,
      });
      const idleId = idle.execution_id as string;
      let idleState = await client.getExecution(idleId);
      const idleStartDeadline = Date.now() + 10000;
      while (idleState.status !== "running" && Date.now() < idleStartDeadline) {
        await delay(50);
        idleState = await client.getExecution(idleId);
      }
      assert.equal(idleState.status, "running");
      const initialPage = await client.readIo(idleId, 0, 0);
      options.progress(`${mode}:short-deadline-read`);
      requestBudgetMs = 6000;
      const boundedReadStarted = performance.now();
      try {
        const boundedPage = await client.readIo(
          idleId,
          initialPage.next_sequence as number,
          20000,
        );
        assert.deepEqual(boundedPage.events, []);
        assert.equal(boundedPage.next_sequence, initialPage.next_sequence);
        assert.equal(boundedPage.terminal, false);
        assert.ok(
          performance.now() - boundedReadStarted < 4000,
          "Response reserve was not applied",
        );
      } finally {
        requestBudgetMs = 30000;
      }
      let settled = false;
      const waiting = client
        .readIo(idleId, initialPage.next_sequence as number, 20000)
        .then(
          () => {
            settled = true;
            return "resolved";
          },
          () => {
            settled = true;
            return "rejected";
          },
        );
      await delay(150);
      assert.equal(settled, false);
      const abandonedAt = Date.now();
      if (mode === "rest") abortController.abort();
      else socket.disconnect();
      assert.equal(await waiting, "rejected");
      assert.ok(Date.now() - abandonedAt < 5000);
      await connect();
      client = new ActionIoReferenceClient(transport, () => options.credential);
      assert.equal(
        (await client.findExecution(options.actionId, idleKey)).execution_id,
        idleId,
      );
      const stillActive = await client.getExecution(idleId);
      assert.equal(
        (stillActive.flags as Record<string, unknown>).terminal,
        false,
      );
      options.progress(`${mode}:resume-abandoned-read`);
      const resumed = await client.readIo(
        idleId,
        initialPage.next_sequence as number,
        0,
      );
      assert.equal(resumed.terminal, false);
      options.progress(`${mode}:input-during-read`);
      let readSettled = false;
      const concurrentRead = client
        .readIo(idleId, resumed.next_sequence as number, 20000)
        .then((page: Record<string, unknown>) => {
          readSettled = true;
          return page;
        });
      await delay(150);
      assert.equal(readSettled, false);
      const inputWhileWaiting = await client.sendInput(
        idleId,
        "input-while-waiting",
        0,
        Uint8Array.from([0, 255, 13, 10, 26]),
      );
      assert.equal(inputWhileWaiting.message_id, "input-while-waiting");
      const releasedPage = await concurrentRead;
      assert.ok(
        Array.isArray(releasedPage.events) && releasedPage.events.length > 0,
      );
      await client.closeInput(idleId, "close-idle", 1);
      let finished = await client.getExecution(idleId);
      const finishDeadline = Date.now() + 10000;
      while (
        !(finished.flags as Record<string, unknown>).terminal &&
        Date.now() < finishDeadline
      ) {
        await delay(50);
        finished = await client.getExecution(idleId);
      }
      assert.equal(finished.status, "succeeded");
      options.progress(`${mode}:cancel-during-read`);
      const cancellable = await client.run(
        options.actionId,
        `cancel-${randomUUID()}`,
        { closeInput: false },
      );
      const cancelId = cancellable.execution_id as string;
      const runningDeadline = Date.now() + 10000;
      let active = await client.getExecution(cancelId);
      while (active.status !== "running" && Date.now() < runningDeadline) {
        await delay(50);
        active = await client.getExecution(cancelId);
      }
      assert.equal(active.status, "running");
      const beforeCancel = await client.readIo(cancelId, 0, 0);
      let cancellationReadSettled = false;
      const cancellationRead = client
        .readIo(cancelId, beforeCancel.next_sequence as number, 20000)
        .then((page: Record<string, unknown>) => {
          cancellationReadSettled = true;
          return page;
        });
      await delay(150);
      assert.equal(cancellationReadSettled, false);
      options.progress(`${mode}:reader-limit`);
      const refusedCommand = {
        jsonrpc: "2.0",
        id: randomUUID(),
        method: "agent.action.readIo",
        params: {
          execution_id: cancelId,
          client_token: options.credential,
          after_sequence: beforeCancel.next_sequence,
          max_bytes: 262144,
          wait_ms: 0,
        },
      };
      const refusedRead = await transport(refusedCommand);
      const { isValidActionIoResponse } = options.requireServer(
        "./src/shared/validators/action_io_result",
      );
      const { captureActionIoExpectation } = options.requireServer(
        "./src/shared/validators/action_io_response_expectation",
      );
      assert.equal(
        isValidActionIoResponse(
          refusedCommand.method,
          refusedRead,
          captureActionIoExpectation(refusedCommand),
        ),
        true,
      );
      assert.equal(
        refusedRead.error?.data?.failure_code,
        "ACTION_IO_READER_LIMIT",
      );
      assert.equal(cancellationReadSettled, false);
      const cancelStarted = Date.now();
      const command = {
        jsonrpc: "2.0",
        id: randomUUID(),
        method: "agent.action.cancel",
        params: { execution_id: cancelId, client_token: options.credential },
      };
      const cancelled = await transport(command);
      assert.equal(
        isValidActionIoResponse(
          command.method,
          cancelled,
          captureActionIoExpectation(command),
        ),
        true,
      );
      const cancellationPage = await cancellationRead;
      assert.ok(Date.now() - cancelStarted < 10000);
      assert.ok(
        Array.isArray(cancellationPage.events) &&
          cancellationPage.events.length > 0,
      );
      let cancelledState = await client.getExecution(cancelId);
      const cancellationDeadline = Date.now() + 10000;
      while (
        !(cancelledState.flags as Record<string, unknown>).terminal &&
        Date.now() < cancellationDeadline
      ) {
        await delay(50);
        cancelledState = await client.getExecution(cancelId);
      }
      assert.equal(cancelledState.status, "cancelled");
      for (const readerLimit of options.thirdCredential &&
      options.foreignCredential
        ? [8, 16]
        : [8]) {
        options.progress(`${mode}:${readerLimit}-reader-saturation`);
        const credentials = Array.from(
          { length: readerLimit + 1 },
          (_, index) =>
            readerLimit === 8 || index < 8
              ? options.credential
              : index < 16
                ? options.foreignCredential!
                : options.thirdCredential!,
        );
        const clients = credentials.map(
          (credential) =>
            new ActionIoReferenceClient(transport, () => credential),
        );
        const saturatedIds: string[] = [];
        const saturatedReads: Array<Promise<Record<string, unknown>>> = [];
        const settledReads = new Set<number>();
        async function controlCancel(id: string): Promise<void> {
          const request = {
            jsonrpc: "2.0",
            id: randomUUID(),
            method: "agent.action.cancel",
            params: {
              execution_id: id,
              client_token: credentials[saturatedIds.indexOf(id)],
            },
          };
          const response = await transport(request);
          assert.equal(
            isValidActionIoResponse(
              request.method,
              response,
              captureActionIoExpectation(request),
            ),
            true,
          );
          assert.equal(response.error, undefined);
        }
        function startWaiting(index: number): Promise<Record<string, unknown>> {
          const pending = clients[index]
            .readIo(saturatedIds[index], 0, 20000)
            .then(
              (page: Record<string, unknown>) => {
                settledReads.add(index);
                return page;
              },
              (error: unknown) => {
                settledReads.add(index);
                throw error;
              },
            );
          // Observe rejection immediately while retaining it for the final assertions.
          pending.catch(() => undefined);
          saturatedReads.push(pending);
          return pending;
        }
        try {
          for (let index = 0; index <= readerLimit; index++) {
            const admitted = await clients[index].run(
              options.actionId,
              `reader-${randomUUID()}`,
              { closeInput: false },
            );
            saturatedIds.push(admitted.execution_id as string);
          }
          for (let index = 0; index < readerLimit; index++) startWaiting(index);
          await delay(300);
          assert.equal(
            settledReads.size,
            0,
            `All ${readerLimit} reads must remain pending`,
          );
          const excessRead = {
            jsonrpc: "2.0",
            id: randomUUID(),
            method: "agent.action.readIo",
            params: {
              execution_id: saturatedIds[readerLimit],
              client_token: credentials[readerLimit],
              after_sequence: 0,
              max_bytes: 65536,
              wait_ms: 0,
            },
          };
          const limited = await transport(excessRead);
          assert.equal(
            isValidActionIoResponse(
              excessRead.method,
              limited,
              captureActionIoExpectation(excessRead),
            ),
            true,
          );
          assert.equal(
            limited.error?.data?.failure_code,
            "ACTION_IO_READER_LIMIT",
          );
          assert.equal(settledReads.size, 0);
          await controlCancel(saturatedIds[readerLimit - 1]);
          const cancelledWaiting = await saturatedReads[readerLimit - 1];
          assert.equal(cancelledWaiting.terminal, true);
          startWaiting(readerLimit);
          await delay(150);
          assert.deepEqual([...settledReads], [readerLimit - 1]);
          const sent = await client.sendInput(
            saturatedIds[0],
            "saturated-input",
            0,
            Uint8Array.from([0, 255, 26]),
          );
          assert.equal(sent.state, "accepted");
          const released = await saturatedReads[0];
          assert.ok(
            (released.events as Array<Record<string, unknown>>).some(
              (event) => event.type === "output",
            ),
          );
          options.progress(`${mode}:${readerLimit}-reader-saturation-passed`);
        } finally {
          // Cancel queued items first so cleanup does not start each pending process.
          for (const id of [...saturatedIds].reverse()) await controlCancel(id);
          const results = await Promise.allSettled(saturatedReads);
          assert.ok(results.every((result) => result.status === "fulfilled"));
        }
      }
    } finally {
      dispose?.();
      socket?.disconnect();
    }
  }
}

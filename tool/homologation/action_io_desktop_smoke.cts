import { spawn } from "node:child_process";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { startDesktopHub } from "./action_io_desktop_hub.cts";
import { verifyReferenceClient } from "./action_io_reference_fixture.cts";

type FixtureSocket = {
  handshake: { auth: { token?: unknown } };
  on(event: string, callback: (raw: unknown) => void): void;
  emit(event: string, payload: unknown): void;
};

// Development-only native bootstrap acceptance. No installer or release proof.
async function main() {
  const serverRoot = realpathSync(process.argv[2]);
  const snapshot = realpathSync(process.argv[3]);
  const checkout = resolve(__dirname, "../..");
  const mode = process.argv[4] ?? "enabled";
  if (mode !== "enabled" && mode !== "disabled")
    throw new Error("Explicit enabled/disabled mode required.");
  const enabled = mode === "enabled";
  const inspect =
    process.argv[5] === "--inspect" || process.argv[5] === "--hub-inspect";
  const soak = process.argv[5] === "--soak";
  const crash = process.argv[5] === "--crash";
  const authenticatedHub =
    process.argv[5] === "--hub" || process.argv[5] === "--hub-inspect";
  const execute = process.argv[5] === "--execute" || crash || authenticatedHub;
  if (execute && !enabled)
    throw new Error("Execution requires explicit enabled mode.");
  if (
    dirname(snapshot) !== join(checkout, "build") ||
    !/^a[a-f0-9]{12}$/.test(basename(snapshot))
  ) {
    throw new Error("Owned development snapshot required.");
  }
  const inventory = JSON.parse(
    readFileSync(join(snapshot, "development-snapshot.json"), "utf8"),
  );
  if (
    inventory.scope !== "uncommitted-development-only" ||
    inventory.productionActivationGate !== false ||
    inventory.identity !==
      `PlugAgenteHomologacao_${basename(snapshot).slice(1)}`
  ) {
    throw new Error("Invalid development snapshot identity.");
  }
  for (const [name, record] of Object.entries(inventory.files) as [
    string,
    { snapshot: string },
  ][]) {
    const path = resolve(snapshot, name);
    if (!path.startsWith(snapshot + "\\") || realpathSync(path) !== path) {
      throw new Error("Invalid development source path.");
    }
    const bytes = readFileSync(path);
    const normalizedLocalization =
      /^lib\/l10n\/app_localizations(?:_en|_pt)?\.dart$/.test(name) &&
      createHash("sha256")
        .update(bytes.toString("utf8").replaceAll("\r\n", "\n"))
        .digest("hex") === record.snapshot;
    if (
      createHash("sha256").update(bytes).digest("hex") !== record.snapshot &&
      !normalizedLocalization
    ) {
      throw new Error(`Development source changed: ${name}`);
    }
  }
  const executable = join(
    snapshot,
    "build/windows/x64/runner/Debug/plug_agente.exe",
  );
  if (!existsSync(executable))
    throw new Error("Compiled development executable required.");
  const root = mkdtempSync(join(tmpdir(), "sql-operation-bootstrap-"));
  process.chdir(root);
  Object.assign(process.env, {
    NODE_ENV: "test",
    CONTAINER_PERSISTENCE_MODE: "memory",
    LOG_LEVEL: "silent",
    DATABASE_URL: "postgresql://fixture:fixture@127.0.0.1:1/unused",
    SMTP_HOST: "127.0.0.1",
    SMTP_PORT: "1",
    ADMIN_EMAIL: "fixture@example.com",
    ENABLE_ACTION_IO_HOMOLOGATION: "true",
    JWT_ACCESS_SECRET: randomBytes(32).toString("hex"),
    JWT_REFRESH_SECRET: randomBytes(32).toString("hex"),
  });
  const requireServer = createRequire(join(serverRoot, "package.json"));
  const { Server } = requireServer("socket.io");
  const { encodePayloadFrame, decodePayloadFrame } = requireServer(
    "./src/shared/utils/payload_frame",
  );
  const { buildHubServerCapabilities } = requireServer(
    "./src/shared/constants/agent_transport_contract",
  );
  const { socketEvents } = requireServer(
    "./src/shared/constants/socket_events",
  );
  const { isValidActionIoResponse } = requireServer(
    "./src/shared/validators/action_io_result",
  );
  const { captureActionIoExpectation } = requireServer(
    "./src/shared/validators/action_io_response_expectation",
  );
  const server = createServer();
  const io = new Server(server, { transports: ["websocket"] });
  const namespace = io.of("/agents");
  const token = randomUUID();
  let protocolReady = false;
  let registrationError = false;
  let connections = 0;
  let heartbeats = 0;
  let agentSocket: FixtureSocket | undefined;
  let rpcSequence = 0;
  let hub: Awaited<ReturnType<typeof startDesktopHub>> | undefined;
  const pending = new Map<string, (response: any) => void>();
  async function call(method: string, params: Record<string, unknown>) {
    if (hub) {
      const response = await fetch(
        `${hub.ready.hubUrl}/api/v1/agents/commands`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${hub.ready.clientAccessToken}`,
          },
          body: JSON.stringify({
            agentId: hub.ready.agentId,
            timeoutMs: 30000,
            command: {
              jsonrpc: "2.0",
              id: `desktop-${++rpcSequence}`,
              method,
              params,
            },
          }),
          signal: AbortSignal.timeout(30000),
        },
      );
      const body = (await response.json()) as any;
      const item = body.response?.item;
      if (body.response?.type !== "single" || !item?.success) {
        throw Object.assign(
          new Error(
            `Authenticated desktop ${method} refused: HTTP ${response.status}, ${item?.error?.code ?? body.error?.code ?? "unspecified"}`,
          ),
          { httpStatus: response.status },
        );
      }
      const normalized = { jsonrpc: "2.0", id: item.id, result: item.result };
      if (
        !isValidActionIoResponse(
          method,
          normalized,
          captureActionIoExpectation({ method, params }),
        )
      ) {
        throw new Error(
          `Authenticated desktop ${method} response violates its schema.`,
        );
      }
      return item.result;
    }
    if (!agentSocket) throw new Error("Desktop RPC peer unavailable.");
    const id = `desktop-${++rpcSequence}`;
    const response = new Promise<any>((done) => pending.set(id, done));
    const timer = setTimeout(
      () => pending.get(id)?.({ error: { code: "fixture_timeout" } }),
      30000,
    );
    try {
      agentSocket.emit(
        socketEvents.rpcRequest,
        encodePayloadFrame({ jsonrpc: "2.0", id, method, params }),
      );
      const result = await response;
      if (result.error)
        throw new Error(
          `Desktop ${method} refused: ${result.error.code}, ${result.error.data?.failure_code ?? "unspecified"}`,
        );
      if (
        !isValidActionIoResponse(
          method,
          result,
          captureActionIoExpectation({ method, params }),
        )
      ) {
        throw new Error(`Desktop ${method} response violates its schema.`);
      }
      return result.result;
    } finally {
      clearTimeout(timer);
      pending.delete(id);
    }
  }
  namespace.use((socket: FixtureSocket, next: (error?: Error) => void) =>
    next(
      socket.handshake.auth.token === token
        ? undefined
        : new Error("Unauthorized"),
    ),
  );
  namespace.on("connection", (socket: FixtureSocket) => {
    agentSocket = socket;
    socket.on(socketEvents.rpcResponse, (raw) => {
      const decoded = decodePayloadFrame(raw);
      if (decoded.ok) {
        const response = decoded.value.data;
        pending.get(String(response.id))?.(response);
      }
    });
    connections++;
    socket.on(socketEvents.agentRegister, (raw) => {
      const decoded = decodePayloadFrame(raw);
      if (
        !decoded.ok ||
        decoded.value.data.agentId !== "agent-bootstrap-test"
      ) {
        registrationError = true;
        return;
      }
      socket.emit(
        socketEvents.agentCapabilities,
        encodePayloadFrame({ capabilities: buildHubServerCapabilities() }),
      );
    });
    socket.on(socketEvents.agentReady, () => {
      protocolReady = true;
    });
    socket.on(socketEvents.agentHeartbeat, (raw) => {
      const decoded = decodePayloadFrame(raw);
      if (
        !decoded.ok ||
        decoded.value.data.agent_id !== "agent-bootstrap-test"
      ) {
        registrationError = true;
        return;
      }
      heartbeats++;
      socket.emit(
        socketEvents.hubHeartbeatAck,
        encodePayloadFrame({
          agent_id: "agent-bootstrap-test",
          timestamp: new Date().toISOString(),
          status: "ok",
          ...(typeof decoded.value.data.trace_id === "string"
            ? { trace_id: decoded.value.data.trace_id }
            : {}),
        }),
      );
    });
    socket.emit(socketEvents.connectionReady, {});
  });
  await new Promise<void>((done) => server.listen(0, "127.0.0.1", done));
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Private listener unavailable.");
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(([key]) =>
      /^(PATH|PATHEXT|SYSTEMROOT|WINDIR|COMSPEC|OS|TEMP|TMP|USERPROFILE|APPDATA|LOCALAPPDATA|PROGRAMDATA|PROGRAMFILES|PROGRAMFILES\(X86\)|PROGRAMW6432|SYSTEMDRIVE)$/i.test(
        key,
      ),
    ),
  );
  const results: unknown[] = [];
  let previous: { instanceId: string; sessionId: string } | undefined;
  let executionCaller:
    | {
        actionId: string;
        credential: string;
        foreignCredential: string;
        thirdCredential?: string;
      }
    | undefined;
  let completedExecution: { id: string; cursor: number } | undefined;
  console.log(`Private desktop evidence: ${root}`);
  try {
    if (authenticatedHub) hub = await startDesktopHub(serverRoot);
    const phases =
      (inspect && !authenticatedHub) || soak
        ? ["cold"]
        : execute
          ? ["cold", "restart"]
          : enabled
            ? ["cold", "restart", "disabled-recovery"]
            : ["cold", "restart"];
    for (const phase of phases) {
      const phaseEnabled = enabled && phase !== "disabled-recovery";
      if (phase === "disabled-recovery") {
        const settingsPath = join(root, "data/settings.json");
        const settings = JSON.parse(readFileSync(settingsPath, "utf8"));
        settings.feature_enable_action_io = false;
        writeFileSync(settingsPath, JSON.stringify(settings));
      }
      protocolReady = authenticatedHub;
      for (const name of [
        "stop",
        "boot-ready.json",
        "boot-closed",
        "boot-failed.json",
      ]) {
        const path = join(root, name);
        if (existsSync(path)) unlinkSync(path);
      }
      const child = spawn(executable, [], {
        cwd: root,
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
        env: {
          ...environment,
          PLUG_AGENT_BOOTSTRAP_ROOT: root,
          PLUG_AGENT_BOOTSTRAP_URL:
            hub?.ready.hubUrl ?? `http://127.0.0.1:${address.port}`,
          PLUG_AGENT_BOOTSTRAP_TOKEN: hub?.ready.agentAuthToken ?? token,
          PLUG_AGENT_BOOTSTRAP_ACTION_IO: phaseEnabled ? "enabled" : "disabled",
          ...(hub
            ? {
                PLUG_AGENT_BOOTSTRAP_HUB_AGENT_ID: hub.ready.agentId,
                PLUG_AGENT_BOOTSTRAP_HUB_CLIENT_ID: hub.ready.clientId,
                PLUG_AGENT_BOOTSTRAP_SECOND_CLIENT_ID: hub.ready.secondClientId,
                PLUG_AGENT_BOOTSTRAP_THIRD_CLIENT_ID: hub.ready.thirdClientId,
              }
            : {}),
          ...(execute && phase === "cold"
            ? { PLUG_AGENT_BOOTSTRAP_ACTION_IO_EXECUTE: "true" }
            : {}),
          ...(inspect || soak || authenticatedHub
            ? { PLUG_AGENT_BOOTSTRAP_INSPECT: "true" }
            : {}),
        },
      });
      let diagnostic = "";
      for (const stream of [child.stdout, child.stderr])
        stream!.on("data", (chunk) => {
          diagnostic = (diagnostic + chunk.toString()).slice(-32768);
        });
      const exited = new Promise<number | null>((done, reject) => {
        child.once("error", reject);
        child.once("close", done);
      });
      try {
        const until = Date.now() + 45000;
        while (!existsSync(join(root, "boot-ready.json")) || !protocolReady) {
          if (
            registrationError ||
            child.exitCode !== null ||
            Date.now() > until
          ) {
            throw new Error(`Desktop readiness failed in ${phase}.`);
          }
          await delay(50);
        }
        const ready = JSON.parse(
          readFileSync(join(root, "boot-ready.json"), "utf8"),
        );
        if (
          !ready.core ||
          !ready.firstFrame ||
          ready.actionIoEnabled !== phaseEnabled ||
          ready.actionIoJournalReady !== enabled ||
          !ready.secretRoundtrip ||
          ready.databaseIntegrity !== "ok" ||
          ready.sqlOperationsDefault !== false ||
          (previous &&
            (previous.instanceId !== ready.instanceId ||
              previous.sessionId === ready.sessionId))
        ) {
          throw new Error(`Desktop evidence failed in ${phase}.`);
        }
        previous = ready;
        if (execute) {
          if (phase === "cold") {
            executionCaller = JSON.parse(
              readFileSync(join(root, "action-io-caller.json"), "utf8"),
            );
            unlinkSync(join(root, "action-io-caller.json"));
          }
          const caller = executionCaller;
          if (!caller) throw new Error("Private execution caller missing.");
          const bytes = Buffer.from([0, 13, 10, 26, 255, 195, 40]);
          const interactive = Buffer.from([255, 0, 26, 10, 13, 128]);
          const runParams = {
            action_id: caller.actionId,
            client_token: caller.credential,
            idempotency_key: "desktop-byte-roundtrip",
            io: {
              version: 1,
              mode: "faithful",
              initial_input_base64: bytes.toString("base64"),
              close_input: false,
            },
          };
          if (hub) {
            const readinessDeadline = Date.now() + 10000;
            for (;;) {
              try {
                await call("agent.action.validateRun", runParams);
                break;
              } catch (error) {
                if (
                  (error as { httpStatus?: number }).httpStatus !== 503 ||
                  Date.now() >= readinessDeadline
                )
                  throw error;
                await delay(100);
              }
            }
          }
          const run = await call("agent.action.run", runParams);
          if (crash) {
            if (
              completedExecution &&
              (run.execution_id !== completedExecution.id ||
                run.io.process_state !== "unknown" ||
                run.io.capture_state !== "incomplete")
            ) {
              throw new Error(
                "Interrupted desktop execution was not reconciled as unknown.",
              );
            }
            const output: Record<string, Buffer[]> = { stdout: [], stderr: [] };
            let crashCursor = 0;
            for (let attempt = 0; attempt < 20; attempt++) {
              const page = await call("agent.action.readIo", {
                execution_id: run.execution_id,
                client_token: caller.credential,
                after_sequence: crashCursor,
                max_bytes: 262144,
                wait_ms: 500,
              });
              if (page.output_complete)
                throw new Error(
                  "Open or interrupted capture reported complete.",
                );
              crashCursor = page.next_sequence;
              for (const event of page.events)
                if (event.type === "output") {
                  if (!(event.stream in output))
                    throw new Error("Unknown crash output stream.");
                  output[event.stream].push(
                    Buffer.from(event.data_base64, "base64"),
                  );
                }
              if (
                Object.values(output).every((chunks) =>
                  Buffer.concat(chunks).equals(bytes),
                )
              )
                break;
            }
            if (
              Object.values(output).some(
                (chunks) => !Buffer.concat(chunks).equals(bytes),
              )
            ) {
              throw new Error("Interrupted desktop output prefix differs.");
            }
            const receipt = await call("agent.action.getInputStatus", {
              execution_id: run.execution_id,
              client_token: caller.credential,
              message_id: run.io.initial_message_id,
            });
            if (
              receipt.state !== "written" ||
              receipt.confirmed_bytes !== bytes.length
            ) {
              throw new Error(
                "Interrupted desktop lost confirmed input receipt.",
              );
            }
            if (phase === "cold") {
              const active = await call("agent.action.getExecution", {
                execution_id: run.execution_id,
                client_token: caller.credential,
              });
              if (active.io.process_state !== "running")
                throw new Error("Crash requires an active native execution.");
              completedExecution = {
                id: run.execution_id,
                cursor: crashCursor,
              };
              if (!child.kill())
                throw new Error("Owned desktop interruption failed.");
              await exited;
              results.push({
                phase,
                ...ready,
                cleanShutdown: false,
                intentionalInterruption: true,
              });
              console.log(
                "PASS: active desktop interrupted after persisted binary output.",
              );
              continue;
            }
            console.log(
              "PASS: interrupted desktop recovered unknown execution and exact persisted bytes.",
            );
          } else {
            if (
              completedExecution &&
              (run.execution_id !== completedExecution.id ||
                run.status !== "succeeded")
            ) {
              throw new Error(
                "Restart did not preserve terminal execution deduplication.",
              );
            }
            const identity = {
              execution_id: run.execution_id,
              client_token: caller.credential,
            };
            for (const [messageId, sequence, payload] of [
              ["desktop-empty", 1, Buffer.alloc(0)],
              ["desktop-interactive", 2, interactive],
            ] as const) {
              await call("agent.action.sendInput", {
                ...identity,
                message_id: messageId,
                sequence,
                data_base64: payload.toString("base64"),
              });
            }
            await call("agent.action.closeInput", {
              ...identity,
              message_id: "desktop-close",
              sequence: 3,
            });
            let cursor = 0;
            const streams: Record<string, Buffer[]> = {
              stdout: [],
              stderr: [],
            };
            let terminal = false;
            for (let attempt = 0; attempt < 20 && !terminal; attempt++) {
              const page = await call("agent.action.readIo", {
                execution_id: run.execution_id,
                client_token: caller.credential,
                after_sequence: cursor,
                max_bytes: 262144,
                wait_ms: 1000,
              });
              cursor = page.next_sequence;
              for (const event of page.events)
                if (event.type === "output") {
                  if (!(event.stream in streams))
                    throw new Error("Unknown desktop output stream.");
                  streams[event.stream].push(
                    Buffer.from(event.data_base64, "base64"),
                  );
                }
              terminal = page.terminal;
              if (terminal && !page.output_complete)
                throw new Error("Desktop capture incomplete.");
            }
            const expected = Buffer.concat([bytes, interactive]);
            if (
              !terminal ||
              Object.values(streams).some(
                (chunks) => !Buffer.concat(chunks).equals(expected),
              )
            ) {
              throw new Error("Desktop binary roundtrip differs.");
            }
            if (completedExecution && cursor !== completedExecution.cursor) {
              throw new Error(
                "Restart or duplicate input appended unexpected events.",
              );
            }
            for (const [messageId, confirmedBytes] of [
              [run.io.initial_message_id, bytes.length],
              ["desktop-empty", 0],
              ["desktop-interactive", interactive.length],
              ["desktop-close", 0],
            ] as const) {
              const receipt = await call("agent.action.getInputStatus", {
                ...identity,
                message_id: messageId,
              });
              if (
                receipt.state !== "written" ||
                receipt.confirmed_bytes !== confirmedBytes
              ) {
                throw new Error("Desktop input delivery receipt differs.");
              }
            }
            const replay = await call("agent.action.run", runParams);
            if (
              replay.execution_id !== run.execution_id ||
              replay.status !== "succeeded"
            )
              throw new Error("Desktop terminal deduplication failed.");
            completedExecution = { id: run.execution_id, cursor };
            console.log(
              "PASS: desktop production bootstrap RPC/native binary roundtrip and terminal deduplication.",
            );
            if (hub && phase === "cold") {
              if (
                typeof caller.thirdCredential !== "string" ||
                !caller.thirdCredential ||
                new Set([
                  caller.credential,
                  caller.foreignCredential,
                  caller.thirdCredential,
                ]).size !== 3 ||
                typeof hub.ready.thirdClientId !== "string" ||
                new Set([
                  hub.ready.clientId,
                  hub.ready.secondClientId,
                  hub.ready.thirdClientId,
                ]).size !== 3
              ) {
                throw new Error(
                  "Three distinct provisioned Clients are required for connection saturation.",
                );
              }
              if (
                typeof caller.foreignCredential !== "string" ||
                !caller.foreignCredential ||
                caller.foreignCredential === caller.credential
              ) {
                throw new Error(
                  "Desktop foreign Client credential is required.",
                );
              }
              if (
                typeof hub.ready.secondClientId !== "string" ||
                !hub.ready.secondClientId ||
                hub.ready.secondClientId === hub.ready.clientId ||
                typeof hub.ready.secondClientAccessToken !== "string" ||
                !hub.ready.secondClientAccessToken ||
                hub.ready.secondClientAccessToken ===
                  hub.ready.clientAccessToken
              ) {
                throw new Error(
                  "Two distinct authenticated hub Clients are required.",
                );
              }
              for (const [
                login,
                accessToken,
                credential,
                foreignCredential,
              ] of [
                [
                  "first",
                  hub.ready.clientAccessToken,
                  caller.credential,
                  caller.foreignCredential,
                ],
                [
                  "second",
                  hub.ready.secondClientAccessToken,
                  caller.foreignCredential,
                  caller.credential,
                ],
              ]) {
                await verifyReferenceClient({
                  requireServer,
                  hubUrl: hub.ready.hubUrl,
                  agentId: hub.ready.agentId,
                  accessToken,
                  credential,
                  foreignCredential,
                  thirdCredential: caller.thirdCredential,
                  actionId: caller.actionId,
                  progress: (stage) =>
                    writeFileSync(
                      join(root, "reference-progress.json"),
                      JSON.stringify({ login, stage }),
                    ),
                });
                console.log(
                  `PASS: ${login} authenticated hub Client REST/socket/relay matrix.`,
                );
              }
              console.log(
                "PASS: reference client REST/socket/relay through authenticated hub and desktop native execution.",
              );
            }
          }
        }
        if (soak) {
          const heartbeatDeadline = Date.now() + 90000;
          while (heartbeats < 3) {
            if (
              child.exitCode !== null ||
              registrationError ||
              connections !== 1 ||
              Date.now() > heartbeatDeadline
            ) {
              throw new Error("Desktop heartbeat continuity failed.");
            }
            await delay(100);
          }
          console.log(
            "PASS: three heartbeat acknowledgements without reconnect.",
          );
        }
        if (inspect) {
          console.log(`READY for inspection: ${root}`);
          const inspectionDeadline = Date.now() + 240000;
          while (!existsSync(join(root, "inspect-complete"))) {
            if (child.exitCode !== null || Date.now() > inspectionDeadline) {
              throw new Error("Desktop inspection was not completed.");
            }
            await delay(100);
          }
          if (hub) {
            if (!executionCaller)
              throw new Error(
                "Inspection requires the private execution caller.",
              );
            await verifyReferenceClient({
              requireServer,
              hubUrl: hub.ready.hubUrl,
              agentId: hub.ready.agentId,
              accessToken: hub.ready.clientAccessToken,
              credential: executionCaller.credential,
              foreignCredential: executionCaller.foreignCredential,
              actionId: executionCaller.actionId,
              progress: (stage) =>
                writeFileSync(
                  join(root, "reference-progress.json"),
                  JSON.stringify({ phase, afterInspection: true, stage }),
                ),
            });
            console.log(
              `PASS: ${phase} fresh remote execution after UI inspection.`,
            );
          }
        }
        writeFileSync(join(root, "stop"), "finish");
        const status = await Promise.race([
          exited,
          delay(15000, "timeout", { ref: false }),
        ]);
        if (
          status !== 0 ||
          readFileSync(join(root, "boot-closed"), "utf8") !== "verified"
        ) {
          throw new Error(`Desktop shutdown failed in ${phase}.`);
        }
        results.push({
          phase,
          ...ready,
          cleanShutdown: true,
          heartbeats,
          connections,
          visualInspection: inspect,
          binaryExecutionVerified: execute,
          interruptedRecoveryVerified: crash,
          authenticatedHubVerified: authenticatedHub,
          distinctHubClientsVerified:
            authenticatedHub && phase === "cold" ? 2 : 0,
          referenceTransportsVerified:
            authenticatedHub && phase === "cold"
              ? ["rest", "socket", "relay"]
              : [],
        });
        console.log(
          `PASS: ${phase}, I/O ${phaseEnabled ? "enabled" : "disabled"}, real AppInitializer and clean shutdown.`,
        );
      } finally {
        writeFileSync(join(root, `${phase}-native.log`), diagnostic);
        if (child.exitCode === null) {
          writeFileSync(join(root, "stop"), "finish");
          const finished = await Promise.race([
            exited,
            delay(10000, "timeout", { ref: false }),
          ]);
          if (finished === "timeout") {
            child.kill();
            await exited;
          }
        }
      }
    }
    writeFileSync(
      join(root, "desktop-result.json"),
      JSON.stringify(
        { success: true, scope: "development-bootstrap", results },
        null,
        2,
      ),
    );
  } finally {
    await new Promise<void>((done) => io.close(done));
    if (hub) await hub.close();
  }
}
main().catch((error) => {
  console.error(
    error instanceof Error ? error.message : "Desktop fixture failed.",
  );
  process.exitCode = 1;
});

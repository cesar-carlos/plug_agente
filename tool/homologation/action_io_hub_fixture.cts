import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  existsSync,
  readFileSync,
  realpathSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import { verifyReferenceClient } from "./action_io_reference_fixture.cts";

// Companion only: real hub routes, disposable identities and memory storage.
async function main(): Promise<void> {
  const root = realpathSync(process.cwd());
  const serverRoot = process.env.ACTION_IO_SERVER_ROOT;
  if (
    !serverRoot ||
    dirname(root) !== realpathSync(tmpdir()) ||
    !/^plug-action-io-[a-f0-9-]{36}$/.test(basename(root)) ||
    process.env.NODE_ENV !== "test" ||
    process.env.CONTAINER_PERSISTENCE_MODE !== "memory" ||
    process.env.ENABLE_ACTION_IO_HOMOLOGATION !== "true" ||
    existsSync(join(root, ".env"))
  ) {
    throw new Error("Explicit isolated I/O fixture environment required.");
  }
  const requireServer = createRequire(
    join(realpathSync(serverRoot), "package.json"),
  );
  const { registerHttpRateLimits } = requireServer(
    "./src/presentation/http/middlewares/rate_limit.middleware",
  );
  registerHttpRateLimits();
  const { createTestServer } = requireServer("./tests/helpers/test_server");
  const { registerOwnerAndClientSession, registerApprovedClientSession } =
    requireServer("./tests/integration/helpers/client_sessions");
  const { seedAgent, seedAgentBinding } = requireServer(
    "./tests/integration/helpers/seed_agent",
  );
  const request = requireServer("supertest");
  const server = await createTestServer();
  // Private fixture only: delay one already-budgeted wire delivery unchanged.
  server.socketIo.of("/agents").on("connection", (socket: {
    emit: (event: string, ...args: unknown[]) => boolean;
  }) => {
    const emit = socket.emit.bind(socket);
    socket.emit = (event: string, ...args: unknown[]) => {
      const marker = join(root, "delay-next-rpc");
      if (event === "rpc:request" && existsSync(marker)) {
        unlinkSync(marker);
        setTimeout(() => emit(event, ...args), 1500);
        return true;
      }
      return emit(event, ...args);
    };
  });
  try {
    const session = await registerOwnerAndClientSession(server.httpServer);
    const secondClient = await registerApprovedClientSession(
      server.httpServer,
      session.owner.email,
    );
    const thirdClient = await registerApprovedClientSession(
      server.httpServer,
      session.owner.email,
    );
    const agentId = randomUUID();
    await seedAgent({
      agentId,
      name: "Isolated action I/O",
      tradeName: "I/O fixture",
      document: "52998224725",
      documentType: "cpf",
      mobile: "11988887777",
      email: "fixture@example.com",
      address: {
        street: "Fixture",
        number: "1",
        district: "Fixture",
        postalCode: "01001000",
        city: "Fixture",
        state: "SP",
      },
    });
    await seedAgentBinding(session.owner.userId, agentId);
    for (const client of [session.client, secondClient, thirdClient]) {
      const access = await request(server.httpServer)
        .post("/api/v1/client/me/agents")
        .set("Authorization", `Bearer ${client.accessToken}`)
        .send({ agentIds: [agentId] });
      if (access.status !== 200 || !access.body.requested.includes(agentId)) {
        throw new Error("Fixture Client access request refused.");
      }
      const pending = await request(server.httpServer)
        .get("/api/v1/me/client-access-requests")
        .set("Authorization", `Bearer ${session.owner.accessToken}`)
        .query({ status: "pending", agentId });
      if (pending.status !== 200 || pending.body.requests.length !== 1) {
        throw new Error("Fixture owner request lookup refused.");
      }
      const approved = await request(server.httpServer)
        .post(
          `/api/v1/me/client-access-requests/${pending.body.requests[0].id}/approve`,
        )
        .set("Authorization", `Bearer ${session.owner.accessToken}`)
        .send({});
      if (approved.status !== 200 || approved.body.approved !== true) {
        throw new Error("Fixture owner approval refused.");
      }
    }
    const login = await request(server.httpServer)
      .post("/api/v1/auth/agent-login")
      .send({
        email: session.owner.email,
        password: session.owner.password,
        agentId,
      });
    if (login.status !== 200) throw new Error("Fixture agent login refused.");
    writeFileSync(
      join(root, "hub-ready.json"),
      JSON.stringify({
        format: "action-io-hub-fixture-v1",
        root,
        hubUrl: server.getUrl(),
        agentId,
        clientId: session.client.clientId,
        clientAccessToken: session.client.accessToken,
        secondClientId: secondClient.clientId,
        secondClientAccessToken: secondClient.accessToken,
        thirdClientId: thirdClient.clientId,
        thirdClientAccessToken: thirdClient.accessToken,
        agentAuthToken: login.body.accessToken,
        productionEnabled: false,
      }),
      { flag: "wx" },
    );
    const deadline = Date.now() + 10 * 60_000;
    let referenceChecked = false;
    const publishReferenceResult = (result: object): void => {
      const next = join(root, "reference-result.next");
      writeFileSync(next, JSON.stringify(result), { flag: "wx" });
      renameSync(next, join(root, "reference-result.json"));
    };
    while (!existsSync(join(root, "hub-stop"))) {
      if (Date.now() >= deadline)
        throw new Error("Fixture controller deadline exceeded.");
      const referencePath = join(root, "reference-request.json");
      if (!referenceChecked && existsSync(referencePath)) {
        referenceChecked = true;
        try {
          if (
            statSync(referencePath).size > 16384 ||
            realpathSync(referencePath) !== referencePath
          )
            throw new Error("Invalid reference request");
          const reference = JSON.parse(readFileSync(referencePath, "utf8"));
          unlinkSync(referencePath);
          if (
            reference.format !== "action-io-reference-v1" ||
            typeof reference.actionId !== "string" ||
            typeof reference.credential !== "string"
          ) {
            throw new Error("Invalid reference request");
          }
          await verifyReferenceClient({
            requireServer,
            hubUrl: server.getUrl(),
            agentId,
            accessToken: session.client.accessToken,
            actionId: reference.actionId,
            credential: reference.credential,
            progress: (stage) =>
              writeFileSync(
                join(root, "reference-progress.json"),
                JSON.stringify({ stage }),
              ),
          });
          for (const mode of ["rest", "socket"]) {
            const args = [join(serverRoot, "node_modules/tsx/dist/cli.mjs"),
              join(serverRoot, "docs/snippets/action_io_echo_client.ts"), mode, join(root, "checkpoint-" + mode)];
            const env = { ...process.env, PLUG_HUB_URL: server.getUrl(), PLUG_AGENT_ID: agentId,
              PLUG_CLIENT_ID: "fixture-client", PLUG_ACTION_NAME: "Second catalog action",
              PLUG_TRIGGER_ID: "second-trigger",
              PLUG_HUB_TOKEN: session.client.accessToken, PLUG_AGENT_TOKEN: reference.credential };
            for (const extra of [["--stop-after-input"], []]) {
              await promisify(execFile)(process.execPath, [...args, ...extra], { env, windowsHide: true, timeout: 45000 });
            }
          }
          publishReferenceResult({
            success: true,
            transports: ["rest", "socket", "relay"],
          });
        } catch (error) {
          publishReferenceResult({
            success: false,
            error: error instanceof Error ? error.name : "unknown",
            code: (error as { code?: unknown })?.code,
            failureCode: (error as { details?: { failure_code?: string } })?.details?.failure_code,
            location:
              error instanceof Error
                ? error.stack
                    ?.split("\n")
                    .find(
                      (line) =>
                        line.trim().startsWith("at ") &&
                        line.includes("action_io_reference_fixture"),
                    )
                : undefined,
          });
        }
      }
      await delay(100);
    }
  } finally {
    await server.close();
  }
}

main().catch((error: unknown) => {
  // Do not print response bodies or the private ready manifest.
  process.stderr.write(
    `Isolated action I/O hub failed (${error instanceof Error ? error.name : "unknown"}).\n`,
  );
  process.exitCode = 1;
});

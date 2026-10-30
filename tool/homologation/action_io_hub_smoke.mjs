import { spawn } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const serverRoot = resolve(process.argv[2] ?? '../plug_server');
const sharedFixture = readFileSync(new URL('../../contracts/action_io_shared_fixtures.json', import.meta.url));
if (!sharedFixture.equals(readFileSync(join(serverRoot, 'contracts/action_io_shared_fixtures.json')))) {
  throw new Error('Agent and hub I/O fixtures differ; synchronize and run both contract suites before homologation.');
}
const callerTransport = process.argv[5] === '--relay' ? 'relay' : process.argv[5] === '--socket' ? 'socket' : 'rest';
const crashWrite = process.argv[6] === '--crash-write';
const crashSpawn = process.argv[6] === '--crash-before-spawn' ? 'before'
  : process.argv[6] === '--crash-after-spawn' ? 'after' : '';
const crash = process.argv[6] === '--crash' || crashWrite || crashSpawn !== '';
const root = join(tmpdir(), `plug-action-io-${randomUUID()}`);
mkdirSync(root);
const env = {};
for (const name of ['SystemRoot', 'WINDIR', 'PATH', 'PATHEXT', 'COMSPEC', 'TEMP', 'TMP',
  'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432', 'SystemDrive']) {
  if (process.env[name]) env[name] = process.env[name];
}
Object.assign(env, {
  NODE_ENV: 'test', CONTAINER_PERSISTENCE_MODE: 'memory',
  DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:1/action_io_unused',
  SMTP_HOST: '127.0.0.1', SMTP_PORT: '1', ADMIN_EMAIL: 'fixture@example.com',
  ENABLE_ACTION_IO_HOMOLOGATION: 'true', ACTION_IO_SERVER_ROOT: serverRoot,
  // The full transport/reference/authorization matrix exceeds the default 100.
  // Keep enforcement finite in this private peer; never alter production defaults.
  REST_AGENTS_COMMANDS_RATE_LIMIT_MAX: '256',
  SOCKET_RELAY_RATE_LIMIT_MAX_REQUESTS: '256',
  JWT_ACCESS_SECRET: randomBytes(32).toString('hex'),
  JWT_REFRESH_SECRET: randomBytes(32).toString('hex'),
  LOG_LEVEL: 'silent',
});
const child = spawn(process.execPath, [
  join(serverRoot, 'node_modules/tsx/dist/cli.mjs'),
  fileURLToPath(new URL('./action_io_hub_fixture.cts', import.meta.url)),
], { cwd: root, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
let diagnostic = '';
for (const stream of [child.stdout, child.stderr]) {
  stream.on('data', (bytes) => { diagnostic = (diagnostic + bytes.toString()).slice(-32768); });
}
let spawnError;
child.on('error', (error) => { spawnError = error; });
const exit = new Promise((done) => child.once('close', (code) => done(code)));
try {
  const deadline = Date.now() + 60_000;
  while (!existsSync(join(root, 'hub-ready.json'))) {
    if (spawnError || child.exitCode !== null || Date.now() >= deadline) {
      writeFileSync(join(root, 'hub-diagnostic.txt'), diagnostic);
      throw new Error(`Hub did not become ready; private diagnostics: ${root}`);
    }
    await delay(100);
  }
  const ready = JSON.parse(readFileSync(join(root, 'hub-ready.json'), 'utf8'));
  if (ready.format !== 'action-io-hub-fixture-v1' || ready.productionEnabled !== false ||
      new URL(ready.hubUrl).hostname !== '127.0.0.1') throw new Error('Invalid fixture readiness.');
  const denied = await fetch(`${ready.hubUrl}/api/v1/agents/commands`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ agentId: ready.agentId, command: {
      jsonrpc: '2.0', id: 'unauthenticated', method: 'agent.action.getExecution',
      params: { execution_id: 'fixture' },
    } }), signal: AbortSignal.timeout(5000),
  });
  if (denied.status !== 401) throw new Error('Unauthenticated request was not refused.');
  if (process.argv[3] === '--native') {
    const dart = process.argv[4];
    if (!dart || !existsSync(dart)) throw new Error('Explicit Flutter Dart executable required.');
    const cache = resolve(dirname(dart), '../..');
    const agentRoot = fileURLToPath(new URL('../../', import.meta.url));
    const native = spawn(dart, [join(cache, 'flutter_tools.snapshot'), 'test', '--no-pub',
      '--timeout', '2m', 'test/infrastructure/actions/action_io_run_test.dart'], {
      cwd: agentRoot, env: { ...env, ACTION_IO_HUB_MANIFEST: join(root, 'hub-ready.json'),
        ACTION_IO_CALLER_TRANSPORT: callerTransport, ACTION_IO_CRASH: String(crash && !crashWrite && !crashSpawn),
        ACTION_IO_CRASH_SPAWN: crashSpawn,
        ACTION_IO_CRASH_WRITE: String(crashWrite) },
      windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let nativeLog = '';
    for (const stream of [native.stdout, native.stderr]) {
      stream.on('data', (bytes) => { nativeLog = (nativeLog + bytes.toString()).slice(-65536); });
    }
    const nativeCode = await new Promise((done, reject) => {
      native.once('error', reject);
      native.once('close', done);
    });
    writeFileSync(join(root, 'native-test.log'), nativeLog);
    if (crash) {
      const checkpoint = join(root, 'crash-checkpoint.json');
      if (nativeCode === 0 || !existsSync(checkpoint)) {
        throw new Error(`Expected interrupted native fixture and durable checkpoint; diagnostics: ${root}`);
      }
      const recovery = spawn(dart, [join(cache, 'flutter_tools.snapshot'), 'test', '--no-pub',
        '--timeout', '2m', 'tool/homologation/action_io_crash_recovery_test.dart'], {
        cwd: agentRoot, env: { ...env, ACTION_IO_CRASH_CHECKPOINT: checkpoint },
        windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
      });
      let recoveryLog = '';
      for (const stream of [recovery.stdout, recovery.stderr]) {
        stream.on('data', (bytes) => { recoveryLog = (recoveryLog + bytes.toString()).slice(-65536); });
      }
      const recoveryCode = await new Promise((done, reject) => {
        recovery.once('error', reject);
        recovery.once('close', done);
      });
      writeFileSync(join(root, 'recovery-test.log'), recoveryLog);
      if (recoveryCode !== 0) throw new Error(`Crash recovery failed; private diagnostics: ${root}`);
      console.log(crashSpawn
        ? `PASS: ${callerTransport} interruption ${crashSpawn} native spawn recovered without replay.`
        : crashWrite
        ? `PASS: ${callerTransport} interrupted native writer recovered with unknown delivery and no replay.`
        : `PASS: ${callerTransport} native interruption recovered in a fresh process with unknown outcome and exact retained bytes.`);
    } else {
      if (nativeCode !== 0) throw new Error(`Native chain failed; private diagnostics: ${root}`);
      const reference = JSON.parse(readFileSync(join(root, 'reference-result.json'), 'utf8'));
      if (reference.success !== true || JSON.stringify(reference.transports) !== '["rest","socket","relay"]') {
        throw new Error('Reference client transport matrix did not pass.');
      }
      console.log('PASS: TypeScript reference client via REST, socket and relay -> authenticated hub -> native Windows process, exact bytes and terminal deduplication.');
      console.log(`PASS: ${callerTransport} caller -> authenticated hub -> agent RPC -> native Windows process, binary output and terminal replay.`);
    }
  }
  writeFileSync(join(root, 'hub-stop'), '');
  const code = await Promise.race([exit, delay(10000, undefined, { ref: false }).then(() => 'timeout')]);
  if (code !== 0) throw new Error('Hub did not shut down cleanly.');
  console.log('PASS: isolated hub registration, owner approval, agent login, auth refusal and shutdown.');
} finally {
  if (child.exitCode === null) {
    writeFileSync(join(root, 'hub-stop'), '');
    const stopped = await Promise.race([exit.then(() => true), delay(10000, undefined, { ref: false }).then(() => false)]);
    if (!stopped) child.kill();
  }
  if (existsSync(join(root, 'hub-ready.json'))) unlinkSync(join(root, 'hub-ready.json'));
  for (const name of ['reference-request.json', 'reference-request.next']) {
    const credentialFile = join(root, name);
    if (existsSync(credentialFile)) unlinkSync(credentialFile);
  }
}

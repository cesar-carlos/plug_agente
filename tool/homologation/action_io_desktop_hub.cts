import { spawn } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

export async function startDesktopHub(serverRoot: string) {
  const root = join(tmpdir(), `plug-action-io-${randomUUID()}`);
  mkdirSync(root);
  const inherited = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    /^(PATH|PATHEXT|SYSTEMROOT|WINDIR|COMSPEC|TEMP|TMP|USERPROFILE|APPDATA|LOCALAPPDATA|PROGRAMFILES|PROGRAMFILES\(X86\)|PROGRAMW6432|SYSTEMDRIVE)$/i.test(key)));
  const child = spawn(process.execPath, [join(serverRoot, 'node_modules/tsx/dist/cli.mjs'),
    join(__dirname, 'action_io_hub_fixture.cts')], {
    cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...inherited, NODE_ENV: 'test', CONTAINER_PERSISTENCE_MODE: 'memory',
      DATABASE_URL: 'postgresql://fixture:fixture@127.0.0.1:1/unused',
      SMTP_HOST: '127.0.0.1', SMTP_PORT: '1', ADMIN_EMAIL: 'fixture@example.com',
      ENABLE_ACTION_IO_HOMOLOGATION: 'true', ACTION_IO_SERVER_ROOT: serverRoot,
      // Two logins exercise 8/16-reader matrices before restart on this private hub.
      REST_AGENTS_COMMANDS_RATE_LIMIT_MAX: '1024', SOCKET_RELAY_RATE_LIMIT_MAX_REQUESTS: '1024',
      REST_GLOBAL_RATE_LIMIT_MAX: '1024',
      JWT_ACCESS_SECRET: randomBytes(32).toString('hex'), JWT_REFRESH_SECRET: randomBytes(32).toString('hex'),
      LOG_LEVEL: 'silent' },
  });
  let diagnostic = '';
  for (const stream of [child.stdout, child.stderr]) stream!.on('data', chunk => {
    diagnostic = (diagnostic + chunk.toString()).slice(-32768);
  });
  let spawnError = false;
  child.on('error', () => { spawnError = true; });
  const exited = new Promise<number | null>(done => child.once('close', done));
  const readyPath = join(root, 'hub-ready.json');
  async function close() {
    writeFileSync(join(root, 'hub-stop'), '');
    const status = await Promise.race([exited, delay(10000, 'timeout', { ref: false })]);
    if (status === 'timeout') { child.kill(); await exited; }
    writeFileSync(join(root, 'hub-diagnostic.txt'), diagnostic);
    if (existsSync(readyPath)) unlinkSync(readyPath);
    if (status !== 0) throw new Error('Private desktop hub shutdown failed.');
  }
  try {
    const deadline = Date.now() + 60000;
    while (!existsSync(readyPath)) {
      if (spawnError || child.exitCode !== null || Date.now() >= deadline) throw new Error('Private desktop hub readiness failed.');
      await delay(100);
    }
    const ready = JSON.parse(readFileSync(readyPath, 'utf8'));
    if (ready.format !== 'action-io-hub-fixture-v1' || ready.productionEnabled !== false ||
        new URL(ready.hubUrl).hostname !== '127.0.0.1') throw new Error('Private hub manifest invalid.');
    return { ready, close };
  } catch (error) {
    await close();
    throw error;
  }
}

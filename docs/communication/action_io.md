# Remote action I/O

Reference for implemented `agentActions.io` v1. Development acceptance completed
on 2026-10-30. The extension remains disabled by default; production activation,
installation and publication are outside this acceptance.

## Sources of truth

- [OpenRPC](openrpc.json) and [method schemas](schemas/) own the wire contract.
- [Binary transport guide](socketio_client_binary_transport.md) owns framing,
  deadlines, correlation and caller behavior.
- This guide owns agent execution, persistence, authorization and recovery.
- [Action tests](../testing/e2e_actions.md) and the procedures below explain verification.
- Hub adapters and reference clients are documented in the sibling server's
  `docs/plug_agente/remote_action_io_specification.md`.

## Operations and authorization

Only locally saved and approved actions with eligible pipe executors may run.
No remote arbitrary commands, runtime parameters, PTY or elevation are enabled.
The approval binds the faithful mode and definition fingerprint; a relevant
change requires fresh approval.

| Method | Behavior |
| --- | --- |
| run | Durable admission, asynchronous launch, original execution on duplicate key, including terminal executions |
| validateRun | Same trigger and I/O selection, read-only validation, preserved would_replay_existing_execution |
| sendInput / closeInput | Durable ordered admission and receipts; close excludes subsequent messages |
| getInputStatus | Current receipt, confirmed byte count and unknown delivery |
| readIo | Persisted whole events, global cursor and per-stream offsets, bounded wait |
| findExecution | Lookup by action/key within the authenticated owner's stable scope |
| getExecution / cancel | Existing contracts plus faithful session state and corresponding permissions |

Every operation requires a current locally provisioned credential, nonempty Client,
agent binding, valid lifetime, no revocation, action allowlist and both
`agent_actions.io` (or explicit wildcard) and the operation scope. Offline JWT
validation alone is insufficient. Rotation preserves access only for the same
Client with current grants. People sharing one Client share ownership.
Authorization is checked at admission, before spawn/write and after long polls.
The journal stores identity references, not raw credentials.

## State and byte semantics

Payloads are original bytes carried as canonical base64 in the existing
JSON-RPC PayloadFrame. No business parsing, encoding conversion, placeholder
substitution or added line endings occur. Text decoding is presentation-only.

Execution, stdin, delivery and capture are independent states. Delivery states
are accepted, writing, written, failed and unknown. ACK means transport receipt;
accepted means committed admission; written means pipe delivery, never program
consumption or business success. Zero exit does not repair incomplete capture.
Global event sequence is observed persistence order, not physical ordering
between stdout and stderr. Empty input is valid and does not close stdin.

## Limits

| Resource | Bound |
| --- | --- |
| Decoded block | 64 KiB |
| Read page | 256 KiB content, 256 events, 512 KiB logical JSON |
| Execution content | 64 MiB total admitted stdin and persisted stdout/stderr |
| Input queue | 16 blocks / 1 MiB |
| Execution records | 8192 messages / 65536 events, including terminal reserve |
| Write / drain | 10 seconds bounded by deadline / 5 seconds |
| Long poll / complete request | 20 seconds / 30 seconds |
| Poll response reserve | 5 seconds for fresh authorization and delivery |
| Readers | 1 per execution/principal, 8 per Client, 16 per connection, 32 per agent |
| Faithful executions | At most 4, subject to stricter existing limits |
| Storage | 1 GiB payload plus separate 256 MiB physical overhead budget |
| Retention after confirmed terminal | Output 24 hours; dedupe at least 3 days |

Enforce serialized frame and negotiated connection limits without relying on
compression. Incompatible peers must not negotiate io. Read events are atomic:
max_bytes must fit one negotiated maximum block; advance only over returned
events. Unknown/active sessions retain reservations until reconciliation.

## Durable lifecycle

Use the separate additive Drift journal (initial schema 1; current schema 2),
WAL and synchronous FULL.
The current configuration database uses NORMAL and must not be treated as a
durable I/O acknowledgment. The journal is authoritative; legacy execution
history is an idempotently repairable projection, not a cross-database transaction.

Encrypt payloads with AES-256-GCM and secure-storage keys. Authenticate execution,
message/stream, sequence and offset through AAD; enforce nonce uniqueness per key.
Missing keys or corrupt ciphertext fail closed. Expiring payload must not remove
deduplication evidence. Account for database/WAL physical size and free disk.

Deduplicate by persistent installation/agent, Client, action and key. Fingerprint
the resolved trigger, approved definition identity, I/O version/mode, initial
bytes and close flag. Compare repeated requests against the original snapshot,
never silently rebase them onto the current action definition.

Initial input uses sequence 0. Automatic close occupies the next sequence.
Reserved message IDs must be returned and queryable. Close admission rejects
later input. Empty input is a message, not EOF. Duplicates do not consume quota.

Native workers retain handle ownership until actual completion; a Dart timeout
does not cancel native I/O. Capture must apply bounded backpressure and persist
before exposing bytes. Cleanup errors cannot replace the primary failure.
Restart reconciles state and projections without recovering pipes or replaying.

## Storage and unknown-outcome recovery

Keep I/O admission disabled while investigating an unavailable journal, missing
key, corrupt payload or exhausted storage. Preserve the database together with
its WAL/SHM and secure-storage key identity; do not copy a live SQLite database
alone and treat that copy as a consistent backup. Use the normal shutdown path
and confirm native ownership has drained before moving or restoring evidence.

- Missing/unreadable key: do not generate a replacement key for a nonempty
  journal, delete the journal or migrate an unrelated vault. Recover the matching
  secure-storage material only through the deployment's approved backup process.
  If unavailable, encrypted bytes remain unavailable and outcomes unresolved.
- Corrupt metadata/ciphertext: retain the original evidence and report the typed
  failure. Do not edit counters, reclassify unknown progress as zero, or salvage
  a partial page as complete. A successful process exit does not repair capture.
- Storage exhaustion: free unrelated disposable data or expand available storage;
  never delete active/unknown I/O evidence or tombstones to permit admission.
  Check both payload and physical file/WAL budgets. Additional free disk does
  not override the configured 1 GiB payload / 256 MiB overhead limits.
- Restart: prepare the matching journal/key and reconcile before enabling I/O.
  Query the original action/key, execution and message IDs. Reopen does not
  recover pipes, restart processes, resend accepted bytes or prove consumption.
- Unknown outcome: preserve the receipt and confirmed prefix exactly. Resolve
  business effects outside the opaque byte bridge before an operator decides
  whether a distinct new execution is appropriate; automatic retry is forbidden.

Physical-volume exhaustion acceptance requires a dedicated bounded disposable
volume and a retained known prefix before exhaustion. Verify refusal, reopen,
prefix preservation and absence of replay. Never fill the workspace/system
volume. The ordinary Windows process is not administrative; the verified
physical-volume run used explicit UAC elevation for the private controller.
Existing SQLite page-limit tests and native free-space probes are narrower
evidence and must not be reported as that physical-volume test.

To execute the prepared case, open administrative PowerShell in this checkout
and run `& ./tool/homologation/action_io_full_volume.ps1`. Optional `-Dart` and
`-FlutterTools` arguments select installed SDK paths. The controller retains its
bounded image under a printed private system-temp directory and dismounts it
even if the test fails. Do not run the Dart test with a manually selected volume
or reuse an operational disk. A zero test/controller exit and the assertions
above are required before closing this acceptance item.

## Reproducing interruption acceptance

Run these commands from the agent checkout on Windows with the sibling hub's
locked dependencies available. Replace `<server-root>` and `<dart-executable>`
with absolute paths. Each controller provisions a new private hub/profile;
never supply operational credentials or reuse an operational journal.

```text
dart test test/infrastructure/stores/action_io_journal_crash_test.dart
node tool/homologation/action_io_hub_smoke.mjs <server-root> --native <dart-executable> --socket --crash-before-spawn
node tool/homologation/action_io_hub_smoke.mjs <server-root> --native <dart-executable> --relay --crash-after-spawn
node tool/homologation/action_io_hub_smoke.mjs <server-root> --native <dart-executable> --relay --crash-write
node tool/homologation/action_io_hub_smoke.mjs <server-root> --native <dart-executable> --socket --crash
```

Run sequentially: Flutter/Dart native-asset preparation can contend for the
SQLite DLL on Windows. A zero controller exit is required; a child termination
alone is not success. The controller requires a durable private checkpoint and
a successful fresh-process recovery before reporting a passed interruption.

| Boundary | Required recovery evidence |
| --- | --- |
| Before/after journal transactions for claim, admission, starting, running, writing, written, stdout, stderr and completion | Only committed state survives; no replay; database integrity remains valid |
| Before native spawn / after suspended native creation, before running commit | Unknown process and incomplete capture; initial input failed with zero confirmed bytes; repeated startup cannot spawn or deliver |
| Blocked native write | Unknown receipt/progress retained; identical message remains unknown; new input refused; no replay after repeated reopen |
| Running process after output commits | Exact persisted stdout/stderr prefix retained; capture remains incomplete; queued input fails and uncertain writing remains unknown |

These fixtures prove the named observable boundaries, not every machine
instruction. They do not certify physical-volume exhaustion or replace the
separate integrated maintenance/shutdown and native-handle cleanup checks.

## Acceptance evidence

The completed plan and chronological work log have been retired. These are the
retained verification results, not permission to enable production:

| Area | Executed evidence |
| --- | --- |
| Agent quality gate | Clean Flutter analyzer; 1,373 contract tests and 264 UI tests |
| Hub quality gate | Lint/typecheck; 2,537 tests passed, 25 unrelated optional skips; dedicated I/O run: 208 tests in 24 suites, no skips |
| Shared contracts | 59 identical fixtures; SHA-256 804a7ed26f8d8f742701bcd085a2bbfcce571f51f6a82e8d5edd595e6d1d5b5f |
| Native and recovery | Exact binary streams, short/blocked writes, descendants, bounded backpressure, 18 journal crash boundaries and native pre/post-spawn/write/output interruptions without replay |
| Hub and desktop | REST/socket/relay reference client through authenticated hub to Windows process; real AppInitializer cold boot/restart, maintenance/shutdown and credential rotation/revocation |
| UI | Rebuilt desktop inspection, approval/reapproval, keyboard, themes and resize; explicit stream downloads each match 131,079 original bytes |
| Physical exhaustion | Private 128 MiB VHD: native disk-full, admission refusal, SQLite failure, exact prefix after reopen, integrity and unknown reconciliation; dismounted successfully |

The operational manifests live under `tool/agent_actions/manifests/`. Focused
coverage includes authorization races, ownership, atomic duplicates/quotas,
cipher/AAD/key loss, retention, projection, deadlines, batches and reader
saturation (1/8/16/32). Required live cases were executed; skips are not evidence.

Local logs are retained under `build/`: `action_io_final_analyzer.log`,
`action_io_final_acceptance_gate.log`, `action_io_server_closure_*.log`,
`action_io_transit_{rest,socket,relay}.log`, `action_io_hint_visual_retry.log`
and `action_io_full_volume_admin.log`. These ignored artifacts are local evidence,
not versioned portable test reports. Rerun the documented controllers when needed.
The volume run identity is `d3de71369bd3456cb77a621cd46ea069`; its system-temp
folder retains test.log, result.json and the dismounted image. Fixture SHA-256:
`B9B8DF13CABAE4C516F2B385518CFD75BF99A534C89CF9412521E20C32782455`.

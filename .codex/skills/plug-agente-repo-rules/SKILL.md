---
name: plug-agente-repo-rules
description: Repository-specific workflow for working in the plug_agente Flutter desktop codebase. Use when implementing, refactoring, reviewing, or testing code in this repository and you need to follow AGENTS.md plus the .cursor/rules ownership model, including architecture boundaries, Dart/Flutter style, UI componentization, Result/Failure error handling, protocol constraints, and test expectations.
---

# Plug Agente Repo Rules

## Overview

Use this skill to navigate the repository guidance without duplicating rule
content. Read the repo entry points first, then load only the rule that owns the
topic you are touching.

## Workflow

1. Read [AGENTS.md](../../../AGENTS.md).
2. Read [rules_index.mdc](../../../.cursor/rules/rules_index.mdc).
3. Read [project_specifics.mdc](../../../.cursor/rules/project_specifics.mdc)
   before code changes that touch architecture, dependencies, transport,
   persistence, runtime, failures, or tests.
4. Load only the thematic rule that owns the task. The catalog is
   `rules_index.mdc`.
5. If multiple topics overlap, keep one owner per theme and let
   `project_specifics.mdc` win only for repository-specific decisions.

## Routing

The ownership table in
[rules_index.mdc](../../../.cursor/rules/rules_index.mdc) is the only catalog.
Do not copy rule names or rule text into this skill.

## Test-Specific Rule

Even for test-only tasks, also read
[project_specifics.mdc](../../../.cursor/rules/project_specifics.mdc).
Repository-specific expectations for `Result<T>`, typed failures, E2E
environment, protocol contracts, and user-safe error messaging live there.

## Sensitive Areas

When touching transport or protocol behavior, also read:

- [socket_communication_standard.md](../../../docs/communication/socket_communication_standard.md)
- [socketio_client_binary_transport.md](../../../docs/communication/socketio_client_binary_transport.md)
- [socket_communication_roadmap.md](../../../docs/communication/socket_communication_roadmap.md)
- [openrpc.json](../../../docs/communication/openrpc.json)

When touching live-style integration tests, also read:

- [e2e_setup.md](../../../docs/testing/e2e_setup.md)
- [e2e_hub.md](../../../docs/testing/e2e_hub.md)
- [e2e_env.dart](../../../test/helpers/e2e_env.dart)

## Working Rules

- Do not copy rule content into new files when a reference to the owner rule is
  enough.
- Do not invent repository conventions from memory; route through
  `rules_index.mdc` and `project_specifics.mdc`.
- Keep user-facing errors clear and actionable, and keep technical context in
  failures/logs.
- For reviews and refactors, check failure paths and behavior contracts, not
  only happy-path code shape.

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
4. Load only the thematic rule that owns the task after the two files above.
5. If multiple topics overlap, keep one owner per theme and let
   `project_specifics.mdc` win only for repository-specific decisions.

## Task Routing

- General code hygiene, naming, duplication, refactoring:
  [general_rules.mdc](../../../.cursor/rules/general_rules.mdc)
- Layering, imports, DTO/domain boundaries, mappings:
  [clean_architecture.mdc](../../../.cursor/rules/clean_architecture.mdc)
- SRP/OCP/LSP/ISP/DIP, code smells, abstraction choices:
  [solid_principles.mdc](../../../.cursor/rules/solid_principles.mdc)
- Dart syntax, modern language features, toolchain, logging:
  [coding_style.mdc](../../../.cursor/rules/coding_style.mdc)
- Nullability and safe optional handling:
  [null_safety.mdc](../../../.cursor/rules/null_safety.mdc)
- Widget structure, shared components, rebuild performance:
  [flutter_widgets.mdc](../../../.cursor/rules/flutter_widgets.mdc)
- Desktop UX, Fluent-first surfaces, visual consistency:
  [ui_ux_design.mdc](../../../.cursor/rules/ui_ux_design.mdc)
- Test strategy and failure-path coverage:
  [testing.mdc](../../../.cursor/rules/testing.mdc)
- Dart/Flutter test harnesses and widget tests:
  [testing_dart_flutter.mdc](../../../.cursor/rules/testing_dart_flutter.mdc)

## Test-Specific Rule

Even for test-only tasks, also read
[project_specifics.mdc](../../../.cursor/rules/project_specifics.mdc).
Repository-specific expectations for `Result<T>`, typed failures, E2E
environment, protocol contracts, and user-safe error messaging live there.

## High-Value Repository Context

- The app is Flutter desktop-first for Windows.
- The app bridges a central hub and local databases through Socket.IO and ODBC.
- Prefer `Provider`, `get_it`, `result_dart`, `drift`, `socket_io_client`,
  `odbc_fast`, `go_router`, and Fluent UI as defined by the repo rules.
- `Result<T>` with typed failures is the official error strategy; do not switch
  to `Either`/`dartz`.
- Reusable UI patterns should evolve through shared components and theme tokens,
  not by duplicating layout.

## Sensitive Areas

When touching transport or protocol behavior, also read:

- [socket_communication_standard.md](../../../docs/communication/socket_communication_standard.md)
- [socketio_client_binary_transport.md](../../../docs/communication/socketio_client_binary_transport.md)
- [socket_communication_roadmap.md](../../../docs/communication/socket_communication_roadmap.md)
- [openrpc.json](../../../docs/communication/openrpc.json)

When touching live-style integration tests, also read:

- [e2e_setup.md](../../../docs/testing/e2e_setup.md)
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

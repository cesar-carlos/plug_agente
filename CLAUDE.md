# Claude Code Entry Point

This file is the entry point for Claude Code in this repository.

## Source of Truth

Canonical rules live in `./.cursor/rules/`.

1. `**./.cursor/rules/rules_index.mdc**` — authoritative index: it lists every
  `.mdc` rule file by category and defines coordination between topics. Start
   here.
2. `**./.cursor/rules/readme.md**` — how the rule set is organized and reused
  across projects.

Use the index to pick the right rule file instead of duplicating or
reinterpreting rules from memory.

## Rule Categories

The category list, ownership per topic, and cross-topic coordination live only
in `./.cursor/rules/rules_index.mdc`. Read it there instead of duplicating the
list here.

## Usage Rules

- Do not rewrite the rules from `./.cursor/rules` here
- If topics overlap, follow the coordination defined in
`./.cursor/rules/rules_index.mdc`
- Treat `./.cursor/rules/project_specifics.mdc` as the source of truth for
packages, transport, failure mapping, and repository conventions
- Do not create new documentation unless explicitly requested

## Notes

- The correct folder is `./.cursor/rules`, not `./.cursor/roles`


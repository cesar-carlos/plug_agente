# Claude Code Entry Point

This file is the entry point for Claude Code in this repository.

## Source of Truth

The canonical coding rules for this project live in:

- `./.cursor/rules/`

Start with:

- `./.cursor/rules/rules_index.mdc`

Use that index to route to the correct rule file instead of duplicating or
reinterpreting rules from memory.

## Rule Categories

### Universal

Use these as language-agnostic guidance:

- `./.cursor/rules/general_rules.mdc`
- `./.cursor/rules/clean_architecture.mdc`
- `./.cursor/rules/solid_principles.mdc`
- `./.cursor/rules/testing.mdc`

### Dart and Flutter

Use these only for Dart/Flutter code:

- `./.cursor/rules/coding_style.mdc`
- `./.cursor/rules/null_safety.mdc`
- `./.cursor/rules/flutter_widgets.mdc`
- `./.cursor/rules/ui_ux_design.mdc`
- `./.cursor/rules/testing_dart_flutter.mdc`

### Project-Specific

Use these for repository-specific decisions:

- `./.cursor/rules/project_specifics.mdc`

## Usage Rules

- Do not rewrite the rules from `./.cursor/rules` here
- If topics overlap, follow the coordination defined in
  `./.cursor/rules/rules_index.mdc`
- Treat `./.cursor/rules/project_specifics.mdc` as the source of truth for
  packages, transport, failure mapping, and repository conventions
- Do not create new documentation unless explicitly requested

## Notes

- The correct folder is `./.cursor/rules`, not `./.cursor/roles`
- `./.cursor/rules/readme.md` explains how the rule set is organized and reused

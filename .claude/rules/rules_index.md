# Rules Index

## Behavioral Guardrails

- ❌ Never commit, push, or create docs unless explicitly requested
- ✅ Prefer self-explanatory code via naming and structure

## Rules (single source of truth per topic)

### Generic (reusable)

- **`general_rules.md`**: core coding principles (readability, duplication, docs/comments policy)
- **`clean_architecture.md`**: layer boundaries and dependency direction (generic)
- **`coding_style.md`**: Dart language/style (naming, formatting, imports, modern Dart, logging, codegen)
- **`null_safety.md`**: sound null-safety guidelines and patterns
- **`solid_principles.md`**: SOLID principles with examples
- **`flutter_widgets.md`**: widget construction/performance patterns (composition, const, lists, layout, theming tokens)
- **`ui_ux_design.md`**: desktop UI/UX principles (Fluent vs Material policy, navigation, a11y, responsive desktop)
- **`testing.md`**: unit/widget testing conventions (AAA, naming, isolation, mocking)

### Project-specific (`backup_database`)

- **`project_specifics.md`**: decisions specific to this repo (Clean Architecture + DDD, dependencies, desktop specifics)

### Templates / other apps

- **`share_app_specifics.md`**: template/example rules for a different app (not applied to this repo)

## Copying to other projects

See `README.md` in this folder. Keep generic rules, and replace `project_specifics.md`.

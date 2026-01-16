# Claude Code Rules - Magic Printer

## 📁 What's This Folder?

This folder contains **project-specific rules and guidelines** for Claude Code AI assistant. These rules help Claude understand the project architecture, coding standards, and patterns to follow when making changes.

**IMPORTANT**: These `.claude/` rules **OVERRIDE** the `.cursor/rules/` directory. Claude Code uses these files as the primary source of truth.

---

## 📂 File Structure

```
.claude/
├── README.md                      # This file - overview
├── PROJECT_GUIDELINES.md          # 🎯 START HERE - Project overview
├── CODING_CONVENTIONS.md          # Naming, style, best practices
├── ARCHITECTURE.md                # Clean Architecture + DDD patterns
├── DEPENDENCIES.md                # Standard libraries (go_router, dio, etc.)
├── CLAUDE_INSTRUCTIONS.md         # Specific instructions for Claude
└── settings.local.json            # Claude settings (auto-generated)
```

---

## 🚀 Quick Start

### For Claude Code AI:

1. **First**, read `PROJECT_GUIDELINES.md` for project overview
2. **Then**, read `CLAUDE_INSTRUCTIONS.md` for specific patterns
3. **Reference** other files as needed:
   - `CODING_CONVENTIONS.md` - When unsure about naming/style
   - `ARCHITECTURE.md` - When working with layers
   - `DEPENDENCIES.md` - When adding libraries

### For Developers:

1. **Read** `PROJECT_GUIDELINES.md` to understand the project
2. **Follow** patterns in `CLAUDE_INSTRUCTIONS.md` when coding
3. **Reference** `.claude/` rules in PR reviews and code reviews
4. **Update** these files when architecture/patterns change

---

## 📋 Rules Summary

### Architecture
- **Clean Architecture** + **Domain Driven Design (DDD)**
- **4 Main Layers**: Domain, Application, Infrastructure, Presentation
- **SOLID Principles**: Single Responsibility, Open/Closed, etc.

### Critical Rules
1. ❌ **NO Flutter in Domain Layer** (pure Dart only)
2. ❌ **NO direct Infrastructure access from Presentation**
3. ❌ **NO magic numbers** (use named constants)
4. ❌ **NO auto-documentation** (code must be self-explanatory)
5. ❌ **NO wrong libraries** (use only specified ones)

### Standard Libraries
| Purpose | Library |
|---------|---------|
| Routes | `go_router` |
| HTTP | `dio` |
| DI | `get_it` |
| State | `Provider` |
| Errors | `result_dart` |
| UUID | `uuid` |
| Env | `flutter_dotenv` |

### Error Handling
- **ALWAYS** use `Result<T>` from `result_dart`
- Return `Success(value)` or `Failure(error)`
- Use `.fold()` to handle both cases

---

## 🔄 Updating These Rules

When the project changes:

1. **Update** the relevant `.md` files
2. **Commit** changes to `.claude/` folder
3. **Inform** team about updates
4. **Archive** old `.cursor/rules/` if deprecated

### What to Update

| Change Type | File to Update |
|-------------|----------------|
| Architecture changes | `ARCHITECTURE.md`, `PROJECT_GUIDELINES.md` |
| New dependencies | `DEPENDENCIES.md` |
| Naming/style changes | `CODING_CONVENTIONS.md` |
| New patterns | `CLAUDE_INSTRUCTIONS.md` |
| General updates | `PROJECT_GUIDELINES.md` |

---

## 🆚 Claude vs Cursor Rules

| Aspect | `.claude/` | `.cursor/rules/` |
|--------|-----------|-----------------|
| **Status** | ✅ **ACTIVE** (primary) | ⚠️ LEGACY (deprecated) |
| **Used by** | Claude Code | Cursor IDE |
| **Priority** | **HIGH** | LOW (backup only) |
| **Updates** | Always update here | Keep for reference |

**Note**: When rules differ between `.claude/` and `.cursor/rules/`, **Claude follows `.claude/`**.

---

## ✅ Checklist

Before committing code, verify:

- [ ] Code follows Clean Architecture
- [ ] Domain layer has NO Flutter/HTTP imports
- [ ] Used only standard libraries (see `DEPENDENCIES.md`)
- [ ] Result<T> used for error handling
- [ ] No magic numbers (use constants)
- [ ] No auto-documentation
- [ ] Dependencies via constructor
- [ ] Proper import order
- [ ] Const constructors in widgets
- [ ] Self-documenting names

---

## 📚 Additional Resources

### Project Documentation
- `.claude/PROJECT_GUIDELINES.md` - Project overview and tech stack
- `.claude/ARCHITECTURE.md` - Detailed architecture patterns
- `.claude/CODING_CONVENTIONS.md` - Naming and style guide
- `.claude/DEPENDENCIES.md` - Standard libraries and patterns
- `.claude/CLAUDE_INSTRUCTIONS.md` - Claude-specific instructions

### Legacy Documentation (Reference Only)
- `.cursor/rules/` - Cursor IDE rules (deprecated for Claude)

### External Resources
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Domain Driven Design](https://www.domainlanguage.com/ddd/)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Effective Dart](https://dart.dev/guides/language/effective-dart)
- [Flutter Best Practices](https://flutter.dev/docs/development/data-and-backend/state-mgmt/options)

---

## 🤝 Contributing

When improving these rules:

1. **Keep it clear** - Use simple, direct language
2. **Show examples** - Good vs Bad comparisons
3. **Stay consistent** - Match existing style
4. **Be specific** - Concrete rules over vague guidelines
5. **Update all** - Ensure changes are reflected in all relevant files

---

## 📞 Support

If you find issues or have questions:

1. Check `PROJECT_GUIDELINES.md` for overview
2. Check `CLAUDE_INSTRUCTIONS.md` for specific patterns
3. Check relevant file for your concern
4. Ask team if still unclear

---

**Last Updated**: 2025-01-08
**Maintained By**: Development Team
**Status**: Active ✅

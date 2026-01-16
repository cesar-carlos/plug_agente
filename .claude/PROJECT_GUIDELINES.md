# Magic Printer - Project Guidelines

## 📋 Overview

This is a Flutter desktop application following **Clean Architecture** + **Domain Driven Design (DDD)** with SOLID principles.

**Tech Stack:**
- Flutter (Fluent UI for Windows)
- Clean Architecture + DDD
- Provider for state management
- go_router for navigation
- get_it for dependency injection
- dio for HTTP
- result_dart for error handling

---

## 🏗️ Architecture

### Layer Structure

```
lib/
├── domain/              # Pure business logic (NO Flutter, NO HTTP)
│   ├── entities/        # Domain objects with identity
│   ├── value_objects/   # Immutable values (Email, CPF, Money)
│   ├── repositories/    # Abstract repositories (interfaces only)
│   ├── use_cases/       # Business operations (SRP, Result<T> return)
│   └── errors/          # Domain failures
│
├── application/         # Orchestration layer
│   ├── services/        # Coordinate use cases
│   ├── dtos/            # Data transfer objects
│   └── mappers/         # Entity ↔ DTO converters
│
├── infrastructure/      # External implementations
│   ├── datasources/     # API, DB, Cache implementations
│   ├── repositories/    # Repository implementations
│   ├── external_services/  # APIs (dio), interceptors
│   └── models/          # Serialization models
│
├── presentation/        # UI layer
│   ├── pages/          # Screens (Stateless/StatefulWidget)
│   ├── widgets/        # UI components
│   └── providers/      # ChangeNotifier (Provider pattern)
│
├── core/               # Shared utilities
│   ├── constants/      # App constants
│   ├── routes/         # go_router config
│   ├── theme/          # App theming
│   └── di/             # get_it service locator
│
└── shared/             # Shared widgets/utils
    └── widgets/        # Reusable components
```

### Dependency Rules (CRITICAL)

```
Presentation → Application → Domain ← Infrastructure
                ↓                    ↓
              Core                Core
```

**Import Rules:**
- ✅ Domain → Core, Shared
- ❌ Domain → Application, Infrastructure, Presentation, Flutter, HTTP

- ✅ Application → Domain, Core, Shared
- ❌ Application → Infrastructure, Presentation

- ✅ Infrastructure → Domain, Core, Shared
- ❌ Infrastructure → Application, Presentation

- ✅ Presentation → Domain, Application, Core, Shared
- ❌ Presentation → Infrastructure

---

## 📦 Standard Dependencies (NEVER Change)

| Purpose | Library | Location |
|---------|---------|----------|
| Routes | `go_router` | `core/routes/` |
| HTTP | `dio` | `infrastructure/external_services/` |
| DI | `get_it` | `core/di/` |
| State | `Provider` | `presentation/providers/` |
| Errors | `result_dart` | All layers (Result<T>) |
| UUID | `uuid` | Domain entities |
| Env | `flutter_dotenv` | `.env` file |

**❌ NEVER use alternatives:**
- Navigator (use go_router)
- BLoC/Riverpod/GetX (use Provider)
- http package (use dio)
- Injectable (use get_it manual registration)

---

## 🎯 Coding Rules

### 1. Documentation
- ❌ **NO automatic documentation** (`///`, README)
- ❌ **NO unnecessary comments**
- ✅ Code MUST be self-explanatory via clear naming
- ✅ Comments ONLY for "why", never "what"

### 2. Magic Numbers
- ❌ **NEVER use magic numbers**
- ✅ **ALWAYS use named constants**

```dart
// ❌ BAD
if (retryCount > 3) { }

// ✅ GOOD
const maxRetries = 3;
if (retryCount > maxRetries) { }
```

### 3. Null Safety
- ✅ Non-null by default
- ✅ Use `?` only when necessary
- ✅ Prefer late initialization over nullable
- ✅ Use `?.` and `??` for null checks

### 4. Const & Final
- ✅ Use `const` for compile-time values
- ✅ Use `const` constructors in widgets
- ✅ Use `final` over `var`

### 5. Naming
- **Entities**: PascalCase singular (`User`, `Product`)
- **Value Objects**: PascalCase (`Email`, `Money`)
- **Use Cases**: PascalCase verbs (`GetUserById`, `CreateOrder`)
- **Repositories**: Prefix `I` for interfaces (`IUserRepository`)
- **Services**: PascalCase + `Service` (`UserService`)
- **DTOs**: PascalCase + `DTO` (`UserDTO`)
- **Files**: snake_case (`user_repository.dart`)

### 6. Widget Rules
- ✅ Prefer `StatelessWidget` over `StatefulWidget`
- ✅ Use `const` constructors
- ✅ Extract widgets when build() > 100 lines
- ✅ Use tear-offs (`UserCard.new`) over functions returning widgets
- ❌ NEVER return Widget from functions

### 7. Error Handling
- ✅ **ALWAYS** use `Result<T>` from `result_dart`
- ✅ Return `Success(value)` or `Failure(error)`
- ✅ Use `.fold()` to handle both cases

```dart
Future<Result<User>> getUser(String id) async {
  if (id.isEmpty) {
    return Failure(ValidationFailure('ID required'));
  }

  try {
    final user = await repository.getById(id);
    return Success(user);
  } catch (e) {
    return Failure(ServerFailure(e.toString()));
  }
}
```

---

## 🔧 Key Patterns

### Use Case Pattern
```dart
// domain/use_cases/get_user_by_id.dart
class GetUserById {
  final IUserRepository repository;

  GetUserById(this.repository);

  Future<Result<User>> call(String id) async {
    if (id.isEmpty) {
      return Failure(ValidationFailure('ID required'));
    }

    return await repository.getById(id);
  }
}
```

### Repository Pattern
```dart
// Domain - Interface
abstract class IUserRepository {
  Future<Result<User>> getById(String id);
}

// Infrastructure - Implementation
class UserRepository implements IUserRepository {
  final IUserDataSource dataSource;

  UserRepository(this.dataSource);

  @override
  Future<Result<User>> getById(String id) async {
    try {
      final model = await dataSource.getById(id);
      return Success(model.toEntity());
    } catch (e) {
      return Failure(ServerFailure(e.toString()));
    }
  }
}
```

### Provider Pattern
```dart
// presentation/providers/user_provider.dart
class UserProvider extends ChangeNotifier {
  final GetUserById _getUserById;

  UserProvider(this._getUserById);

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadUser(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _getUserById(id);

    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
      },
      (user) {
        _user = user;
        _isLoading = false;
      },
    );

    _isLoading = false;
    notifyListeners();
  }
}
```

---

## ✅ Code Review Checklist

Before committing code, verify:

- [ ] Domain has NO Flutter/HTTP imports
- [ ] Application has NO Infrastructure/Presentation imports
- [ ] Infrastructure has NO Application/Presentation imports
- [ ] Presentation has NO Infrastructure imports
- [ ] All classes have SINGLE responsibility (SRP)
- [ ] Dependencies injected via constructor (DIP)
- [ ] Interfaces used, not concrete classes (DIP)
- [ ] Result<T> used for error handling
- [ ] NO magic numbers (use constants)
- [ ] NO unnecessary comments
- [ ] NO automatic documentation
- [ ] go_router used for navigation
- [ ] Provider used for state
- [ ] dio used for HTTP
- [ ] get_it used for DI

---

## 🚨 Critical Rules Summary

1. **Domain Layer**: Pure Dart, NO Flutter, NO HTTP, NO external deps
2. **Dependencies**: Use ONLY specified libraries (go_router, dio, Provider, get_it, result_dart)
3. **Error Handling**: ALWAYS use Result<T>, NEVER exceptions for flow control
4. **Documentation**: NO automatic docs, code MUST be self-explanatory
5. **Magic Numbers**: ALWAYS use named constants
6. **Widgets**: Prefer const, use tear-offs, extract when large

---

## 📚 Reference Documents

- `.cursor/rules/` - Original Cursor rules (deprecated for Claude)
- See individual files in `.claude/` for detailed patterns

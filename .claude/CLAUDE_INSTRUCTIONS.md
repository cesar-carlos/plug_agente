# Claude Code - Specific Instructions

## 🤖 Instructions for Claude Code AI Assistant

When working on this project, follow these specific guidelines:

---

## 1. File Structure Understanding

```
D:\Developer\Flutter\magic_printer\
├── lib/
│   ├── domain/           # Pure business logic (NO Flutter!)
│   ├── application/      # Orchestration layer
│   ├── infrastructure/   # External implementations
│   ├── presentation/     # UI (Fluent UI)
│   ├── core/            # Routes, DI, Theme, Constants
│   └── shared/          # Shared widgets
├── .cursor/rules/       # Cursor rules (legacy)
└── .claude/             # Claude rules (ACTIVE - use these!)
```

---

## 2. Critical Rules (NEVER Violate)

### ❌ NEVER Do These Things

1. **NO Flutter in Domain Layer**
   ```dart
   // ❌ WRONG
   // domain/entities/user.dart
   import 'package:flutter/material.dart';  // ERROR!

   // ✅ CORRECT
   // domain/entities/user.dart
   // Pure Dart only, NO Flutter imports
   ```

2. **NO Direct Infrastructure Access from Presentation**
   ```dart
   // ❌ WRONG
   // presentation/pages/user_page.dart
   import 'package:infrastructure/repositories/user_repository.dart';

   // ✅ CORRECT
   // presentation/pages/user_page.dart
   import 'package:application/application.dart';  // Use services
   ```

3. **NO Magic Numbers**
   ```dart
   // ❌ WRONG
   if (retryCount > 3) { }

   // ✅ CORRECT
   const maxRetries = 3;
   if (retryCount > maxRetries) { }
   ```

4. **NO Auto-Documentation**
   ```dart
   // ❌ WRONG
   /// Service for managing users.
   ///
   /// This service provides CRUD operations for users.
   class UserService { }

   // ✅ CORRECT
   class UserService { }  // Self-documenting name
   ```

5. **NO Wrong Libraries**
   ```dart
   // ❌ WRONG
   import 'package:bloc/bloc.dart';
   import 'package:http/http.dart';
   Navigator.push(context, ...);

   // ✅ CORRECT
   import 'package:provider/provider.dart';
   import 'package:dio/dio.dart';
   context.go('/route');
   ```

---

## 3. When Refactoring Code

### Step 1: Check Import Rules
```dart
// ✅ CORRECT import order
// 1. Dart SDK
// 2. Flutter
// 3. External packages (go_router, dio, provider, get_it, result_dart)
// 4. Core
// 5. Domain
// 6. Application
// 7. Relative imports
```

### Step 2: Verify Layer Compliance
- Domain → NO Flutter, NO HTTP, NO other layers except Core/Shared
- Application → NO Infrastructure, NO Presentation
- Infrastructure → NO Application, NO Presentation
- Presentation → NO Infrastructure

### Step 3: Check for Common Issues
- [ ] No magic numbers
- [ ] Result<T> used for errors
- [ ] Dependencies via constructor
- [ ] const constructors in widgets
- [ ] Tear-offs instead of widget functions
- [ ] No unnecessary comments
- [ ] Self-documenting names

---

## 4. Code Patterns

### Creating a New Feature

```dart
// 1. Create Domain Entity
// domain/entities/feature.dart
class Feature {
  final String id;
  final String name;

  const Feature({required this.id, required this.name});
}

// 2. Create Repository Interface
// domain/repositories/i_feature_repository.dart
abstract class IFeatureRepository {
  Future<Result<List<Feature>>> getAll();
}

// 3. Create Use Case
// domain/use_cases/get_features.dart
class GetFeatures {
  final IFeatureRepository repository;

  GetFeatures(this.repository);

  Future<Result<List<Feature>>> call() async {
    return await repository.getAll();
  }
}

// 4. Implement Repository
// infrastructure/repositories/feature_repository.dart
class FeatureRepository implements IFeatureRepository {
  final FeatureDataSource dataSource;

  FeatureRepository(this.dataSource);

  @override
  Future<Result<List<Feature>>> getAll() async {
    try {
      final data = await dataSource.getAll();
      return Success(data);
    } catch (e) {
      return Failure(ServerFailure(e.toString()));
    }
  }
}

// 5. Create Provider
// presentation/providers/feature_provider.dart
class FeatureProvider extends ChangeNotifier {
  final GetFeatures _getFeatures;

  FeatureProvider(this._getFeatures);

  List<Feature> _features = [];
  List<Feature> get features => _features;

  Future<void> loadFeatures() async {
    final result = await _getFeatures();

    result.fold(
      (failure) => print('Error: ${failure.message}'),
      (features) {
        _features = features;
        notifyListeners();
      },
    );
  }
}

// 6. Register DI
// core/di/service_locator.dart
getIt.registerLazySingleton<IFeatureRepository>(
  () => FeatureRepository(getIt<FeatureDataSource>()),
);
getIt.registerFactory(() => GetFeatures(getIt<IFeatureRepository>()));

// 7. Create Page
// presentation/pages/features_page.dart
class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FeatureProvider>(
      builder: (context, provider, child) {
        return ListView.builder(
          itemCount: provider.features.length,
          itemBuilder: (context, index) {
            final feature = provider.features[index];
            return ListTile(title: Text(feature.name));
          },
        );
      },
    );
  }
}
```

---

## 5. Common Fixes

### Fixing "Widget Function" Anti-Pattern

```dart
// ❌ BEFORE
Widget buildCard(User user) {
  return Card(child: Text(user.name));
}

// Usage
ListView.builder(
  itemBuilder: (context, index) => buildCard(users[index]),
)

// ✅ AFTER
class UserCard extends StatelessWidget {
  final User user;
  const UserCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(child: Text(user.name));
  }
}

// Usage
ListView.builder(
  itemBuilder: (context, index) => UserCard(user: users[index]),
)
```

### Fixing Direct Infrastructure Access

```dart
// ❌ BEFORE
// presentation/pages/user_page.dart
import 'package:infrastructure/repositories/user_repository.dart';

class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = UserRepository();  // WRONG!
    // ...
  }
}

// ✅ AFTER
// presentation/pages/user_page.dart
import 'package:application/application.dart';

class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context);  // CORRECT!
    // ...
  }
}
```

---

## 6. Error Handling Pattern

```dart
// ✅ ALWAYS use Result<T>
Future<Result<User>> getUser(String id) async {
  // Validation
  if (id.isEmpty) {
    return Failure(ValidationFailure('ID is required'));
  }

  try {
    final user = await repository.getById(id);
    return Success(user);
  } catch (e) {
    return Failure(ServerFailure(e.toString()));
  }
}

// ✅ Handle Result
final result = await getUser('123');

result.fold(
  (failure) {
    // Show error to user
    showErrorBar(failure.message);
  },
  (user) {
    // Update UI with user data
    updateUserDisplay(user);
  },
);

// ✅ Or check first
if (result.isSuccess()) {
  final user = result.getOrNull();
} else {
  final failure = result.exceptionOrNull();
}
```

---

## 7. Navigation Pattern

```dart
// ✅ Use go_router
// core/routes/app_router.dart
final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/hosts/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return HostDetailsPage(hostId: id);
      },
    ),
  ],
);

// Usage
context.go('/hosts/123');        // Navigate
context.push('/settings');         // Add to stack
context.pop();                     // Go back
```

---

## 8. Widget Best Practices

```dart
// ✅ Prefer StatelessWidget
class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Hello');  // const when possible
  }
}

// ✅ Extract large widgets
class BigWidget extends StatelessWidget {
  const BigWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HeaderWidget(),
        ContentWidget(),
        FooterWidget(),
      ],
    );
  }
}

// ✅ Use tear-offs
itemBuilder: (context, index) => UserCard(user: users[index])

// ✅ Const constructors
const SizedBox(height: 16);
const Text('Title');
```

---

## 9. When You See These Issues, Fix Them

| Issue | Fix |
|-------|-----|
| `import 'package:flutter/...'` in domain | Remove, use pure Dart |
| `import 'package:infrastructure/...'` in presentation | Import from application instead |
| `if (x > 3)` | Create `const maxNumber = 3` |
| `Widget buildX()` | Create `class XWidget extends StatelessWidget` |
| `throw Exception()` | Use `return Failure(...)` |
| `Navigator.push()` | Use `context.go()` or `context.push()` |
| `/// Documentation` | Remove unless explicitly requested |
| `var x =` | Use `final x =` or `const x =` |

---

## 10. Quick Checklist for Code Reviews

```
Domain Layer:
  [ ] Pure Dart only (no Flutter!)
  [ ] No HTTP imports
  [ ] Entities, Value Objects, Use Cases, Repository interfaces
  [ ] Result<T> for errors

Application Layer:
  [ ] Services coordinate use cases
  [ ] DTOs for data transfer
  [ ] No Infrastructure/Presentation imports

Infrastructure Layer:
  [ ] Implements Domain interfaces
  [ ] Data sources handle HTTP/DB
  [ ] Models convert to/from Entities

Presentation Layer:
  [ ] Providers manage UI state
  [ ] Pages are UI only
  [ ] No Infrastructure imports
  [ ] Uses go_router for navigation

General:
  [ ] No magic numbers
  [ ] No auto-documentation
  [ ] const constructors
  [ ] Tear-offs for widgets
  [ ] Self-documenting names
  [ ] Proper import order
```

---

## 📚 Reference Files

- `.claude/PROJECT_GUIDELINES.md` - Start here!
- `.claude/CODING_CONVENTIONS.md` - Naming and style
- `.claude/ARCHITECTURE.md` - Layer patterns
- `.claude/DEPENDENCIES.md` - Standard libraries

---

## 🚨 Emergency Rules

If you're unsure:
1. Check `.claude/PROJECT_GUIDELINES.md`
2. Follow Clean Architecture principles
3. Use Result<T> for errors
4. Inject dependencies via constructor
5. When in doubt, ASK the user!

---

**Remember**: These `.claude/` rules OVERRIDE any `.cursor/rules/`. Always prioritize `.claude/` files.

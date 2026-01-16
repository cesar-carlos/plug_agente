# Coding Conventions - Magic Printer

## 🎯 Core Principles

1. **Self-Documenting Code**: Names should explain WHAT, comments only explain WHY
2. **SOLID Compliance**: Every class follows SOLID principles
3. **No Magic Numbers**: Always use named constants
4. **Result Pattern**: Use `Result<T>` for error handling
5. **Dependency Inversion**: Depend on abstractions (interfaces)

---

## 📝 Naming Conventions

### Classes & Types

```dart
// ✅ PascalCase for classes
class UserService { }
class UserDTO { }
class GetUserById { }

// ✅ Prefix 'I' for interfaces
abstract class IUserRepository { }
abstract class IDataSource { }

// ✅ Suffixes for clarity
class UserProvider extends ChangeNotifier { }
class UserModel { }  // Infrastructure model
class User { }        // Domain entity
```

### Variables & Methods

```dart
// ✅ camelCase
final String userName = 'John';
final List<User> userList = [];
Future<void> getUserById() async { }

// ✅ Private with underscore
final String _privateField = '';
void _privateMethod() { }

// ✅ Constants - lowerCamelCase with const
const maxRetries = 3;
const defaultTimeout = Duration(seconds: 30);

// ✅ Static constants in classes
class AppConstants {
  static const int maxRetries = 3;
  static const Duration defaultTimeout = Duration(seconds: 30);
}
```

### Files

```dart
// ✅ snake_case matching main class
user.dart                    → class User
user_repository.dart         → class UserRepository
i_user_repository.dart       → abstract class IUserRepository
get_user_by_id.dart          → class GetUserById
email.dart                   → class Email (value object)
```

---

## 🚫 Anti-Patterns to Avoid

### ❌ Magic Numbers

```dart
// ❌ BAD
if (retryCount > 3) { }
await Future.delayed(Duration(seconds: 30));
if (port < 1 || port > 65535) { }

// ✅ GOOD
const maxRetries = 3;
const defaultTimeout = Duration(seconds: 30);
const minPort = 1;
const maxPort = 65535;

if (retryCount > maxRetries) { }
await Future.delayed(defaultTimeout);
if (port < minPort || port > maxPort) { }
```

### ❌ Unnecessary Comments

```dart
// ❌ BAD - explains WHAT
// Get user from repository
final user = await repository.getUser(id);

// Increment counter
_counter++;

// ✅ GOOD - self-explanatory
final user = await repository.getUser(id);
_counter++;

// ✅ GOOD - explains WHY (rare)
// Use local cache to reduce API calls by 80%
final user = await cache.getUser(id);
```

### ❌ Automatic Documentation

```dart
// ❌ BAD - auto-generated docs
/// Service for managing user operations.
///
/// This service provides methods to create, update, and delete users.
class UserService {
  /// Creates a new user with the given [name] and [email].
  ///
  /// Returns the created [User] if successful, or throws an exception.
  Future<User> createUser({required String name, required String email}) async { }
}

// ✅ GOOD - self-documenting
class UserService {
  Future<User> createUser({required String name, required String email}) async { }
}
```

---

## ✅ Best Practices

### 1. Result Pattern for Error Handling

```dart
// ✅ ALWAYS use Result<T>
import 'package:result_dart/result_dart.dart';

Future<Result<User>> getUser(String id) async {
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

// Usage
final result = await getUser('123');
result.fold(
  (failure) => print('Error: ${failure.message}'),
  (user) => print('User: ${user.name}'),
);
```

### 2. Dependency Injection via Constructor

```dart
// ✅ Inject dependencies via constructor
class UserService {
  final IUserRepository repository;

  UserService(this.repository);
}

// ✅ Use named parameters for clarity
class CreateUser {
  final IUserRepository repository;
  final IEmailService emailService;

  CreateUser({
    required this.repository,
    required this.emailService,
  });
}
```

### 3. Const Constructors

```dart
// ✅ Use const whenever possible
class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text('Hello'),
        SizedBox(height: 16),
      ],
    );
  }
}
```

### 4. Tear-offs Instead of Widget Functions

```dart
// ❌ BAD - function returning Widget
Widget buildUserCard(User user) {
  return UserCard(user: user);
}

// Usage
itemBuilder: (context, index) => buildUserCard(users[index])

// ✅ GOOD - use tear-off
itemBuilder: (context, index) => UserCard(user: users[index])
// or
itemBuilder: UserCard.new  // if no parameters needed
```

### 5. Null Safety

```dart
// ✅ Non-null by default
String userName = 'John';
final int age = 25;

// ✅ Nullable only when necessary
String? optionalEmail;
User? currentUser;

// ✅ Null-aware operators
final email = optionalEmail ?? '';
final name = currentUser?.name ?? 'Anonymous';

// ✅ Late initialization
late String userName;
void init() {
  userName = 'John';
}
```

---

## 📦 Import Organization

### Import Order

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:convert';

// 2. Flutter
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart';

// 3. External packages
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:result_dart/result_dart.dart';

// 4. Core
import 'package:magic_printer/core/core.dart';

// 5. Domain
import 'package:magic_printer/domain/domain.dart';

// 6. Application
import 'package:magic_printer/application/application.dart';

// 7. Relative (same layer)
import '../widgets/user_card.dart';
import '../providers/user_provider.dart';
```

---

## 🎨 Widget Conventions

### Prefer StatelessWidget

```dart
// ✅ Prefer StatelessWidget when possible
class UserCard extends StatelessWidget {
  final User user;

  const UserCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(user.name),
        subtitle: Text(user.email),
      ),
    );
  }
}
```

### Extract Large Widgets

```dart
// ❌ BAD - build() too large (>100 lines)
class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 200 lines of widgets...
        ],
      ),
    );
  }
}

// ✅ GOOD - extract to smaller widgets
class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          UserHeader(user: user),
          UserStats(user: user),
          UserActions(user: user),
        ],
      ),
    );
  }
}
```

---

## 🔒 Domain Layer Rules

### Pure Dart Only

```dart
// ✅ GOOD - pure Dart, no Flutter/HTTP
// domain/entities/user.dart
class User {
  final String id;
  final String name;
  final Email email;

  const User({
    required this.id,
    required this.name,
    required this.email,
  });

  // Business logic here
  bool get isActive => email.value.isNotEmpty;
}

// ❌ BAD - Flutter import in domain
import 'package:flutter/material.dart';  // ❌ ERROR

class User {
  final String name;
  Widget buildWidget() { ... }  // ❌ ERROR
}
```

### Value Objects

```dart
// ✅ GOOD - immutable value object
class Email {
  final String value;

  Email(this.value) {
    if (!isValid(value)) {
      throw InvalidEmailException('Invalid email: $value');
    }
  }

  static bool isValid(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Email && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

---

## ✅ Checklist

Before committing code:

- [ ] No magic numbers (use constants)
- [ ] No unnecessary comments
- [ ] No auto-generated documentation
- [ ] Result<T> used for error handling
- [ ] Dependencies via constructor
- [ ] Interfaces (not concrete classes) in constructors
- [ ] const constructors used
- [ ] Tear-offs instead of widget functions
- [ ] Proper import order
- [ ] Domain layer has NO Flutter/HTTP imports
- [ ] Classes have single responsibility
- [ ] Self-documenting names

---

## 📚 Related Documents

- `PROJECT_GUIDELINES.md` - Architecture overview
- `DEPENDENCIES.md` - Standard libraries
- `ARCHITECTURE.md` - Detailed architecture patterns

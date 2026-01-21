# SOLID Principles

## Single Responsibility Principle (SRP)

Each class should have one reason to change. A class should have a single, well-defined responsibility.

**Application:**
- Separate business logic from data access
- Separate UI logic from business logic
- Avoid "God Class" that does everything

**Example:**

```dart
// ✅ Correct: Each class has single responsibility
class User {
  final String id;
  final String name;
  // Only responsible for representing a user
}

class UserValidator {
  bool validate(User user) {
    // Only responsible for validating user
  }
}

class UserRepository {
  Future<User> save(User user) {
    // Only responsible for persistence
  }
}
```

```dart
// ❌ Incorrect: One class doing too much
class UserManager {
  String name;
  String email;

  void validate() { /* validation logic */ }
  void saveToDatabase() { /* persistence logic */ }
  void updateUI() { /* UI logic */ }
}
```

## Open/Closed Principle (OCP)

Classes should be open for extension but closed for modification. Extend behavior without modifying existing code.

**Application:**
- Use interfaces and abstract classes
- Add new behavior through inheritance or composition
- Never modify tested/working code to add features

**Example:**

```dart
// ✅ Correct: Extend through interface
abstract class PaymentMethod {
  Future<void> pay(double amount);
}

class CreditCard implements PaymentMethod {
  @override
  Future<void> pay(double amount) { /* implementation */ }
}

class PayPal implements PaymentMethod {
  @override
  Future<void> pay(double amount) { /* implementation */ }
}

// Add new payment method without modifying existing code
class Pix implements PaymentMethod {
  @override
  Future<void> pay(double amount) { /* implementation */ }
}
```

## Liskov Substitution Principle (LSP)

Subtypes must be substitutable for their base types. Any instance of a subclass should be usable where the parent class is expected.

**Application:**
- Maintain behavioral contracts
- Don't change method signatures in ways that break parent expectations
- Use interfaces to define clear contracts

**Example:**

```dart
// ✅ Correct: Subtypes are substitutable
import 'dart:developer' as developer;

abstract class Animal {
  void makeSound();
}

class Dog implements Animal {
  @override
  void makeSound() => developer.log('Woof!');
}

class Cat implements Animal {
  @override
  void makeSound() => developer.log('Meow!');
}

// Any Animal can be used here
void makeAnimalSound(Animal animal) {
  animal.makeSound(); // Works with Dog, Cat or any subtype
}
```

```dart
// ❌ Incorrect: Subtype breaks parent contract
class Bird implements Animal {
  @override
  void makeSound() => throw UnimplementedError();
}
```

## Interface Segregation Principle (ISP)

Many specific interfaces are better than one general interface. Clients should not be forced to depend on interfaces they don't use.

**Application:**
- Break down large interfaces into smaller, focused ones
- Each interface should be cohesive and relevant to a specific concern
- Prefer composition over large, monolithic interfaces

**Example:**

```dart
// ✅ Correct: Small, focused interfaces
abstract class Readable {
  Future<String> read();
}

abstract class Writable {
  Future<void> write(String data);
}

// Class implements only what it needs
class FileReader implements Readable {
  @override
  Future<String> read() { /* implementation */ }
}

class FileRW implements Readable, Writable {
  @override
  Future<String> read() { /* implementation */ }

  @override
  Future<void> write(String data) { /* implementation */ }
}
```

```dart
// ❌ Incorrect: Large interface forcing unnecessary implementations
abstract class FileHandler {
  Future<String> read();
  Future<void> write(String data);
  Future<void> delete();
  Future<void> copy(String path);
}

class FileReader implements FileHandler {
  @override
  Future<String> read() { /* implementation */ }

  @override
  Future<void> write(String data) { /* Not needed, but forced to implement */ }
  @override
  Future<void> delete() { /* Not needed, but forced to implement */ }
  @override
  Future<void> copy(String path) { /* Not needed, but forced to implement */ }
}
```

## Dependency Inversion Principle (DIP)

High-level modules should not depend on low-level modules. Both should depend on abstractions. Abstractions should not depend on details; details should depend on abstractions.

**Application:**
- Define interfaces in Domain (high-level layer)
- Implement interfaces in Infrastructure (low-level layer)
- Inject dependencies via constructor
- Use dependency injection containers when appropriate

**Example:**

```dart
// ✅ Correct: High-level depends on abstraction
// Domain - Interface (abstraction)
abstract class IUserRepository {
  Future<User> getById(String id);
}

// Application - Depends on abstraction
class UserService {
  final IUserRepository repository; // Interface, not implementation

  UserService(this.repository);

  Future<User> getUser(String id) {
    return repository.getById(id);
  }
}

// Infrastructure - Implements abstraction
class UserRepository implements IUserRepository {
  @override
  Future<User> getById(String id) { /* implementation */ }
}
```

```dart
// ❌ Incorrect: High-level depends on implementation
class UserService {
  final UserRepository repository; // Concrete implementation, not interface

  UserService(this.repository);

  Future<User> getUser(String id) {
    return repository.getById(id);
  }
}
```

## SOLID in Clean Architecture

| Layer | SOLID Application |
|--------|------------------|
| **Domain** | SRP (entities with single responsibility), DIP (defines interfaces), ISP (focused repository interfaces) |
| **Application** | SRP (services coordinate specific use cases), DIP (depends on domain interfaces) |
| **Infrastructure** | DIP (implements domain interfaces), LSP (implementations are substitutable) |
| **Presentation** | SRP (widgets/pages have single responsibility), ISP (focused providers) |

## Checklist

When reviewing code for SOLID compliance:

- [ ] SRP: Each class has one reason to change
- [ ] SRP: Classes have a single, well-defined responsibility
- [ ] OCP: New functionality added through extension, not modification
- [ ] OCP: Interfaces and abstract classes used for extension
- [ ] LSP: Subtypes can replace parent types without breaking behavior
- [ ] LSP: Method signatures maintain parent contracts
- [ ] ISP: Interfaces are small and focused
- [ ] ISP: Classes don't implement methods they don't use
- [ ] DIP: High-level modules depend on abstractions
- [ ] DIP: Dependencies are injected via constructor
- [ ] DIP: Interfaces defined in Domain, implemented in Infrastructure

## Common Violations

❌ **SRP Violations**:
- Classes that handle business logic, data access, and UI together
- Methods that do multiple unrelated operations

❌ **OCP Violations**:
- Modifying existing classes to add new features
- Using extensive `if-else` or `switch` statements instead of polymorphism

❌ **LSP Violations**:
- Subtypes throwing exceptions not expected in parent
- Subtypes changing the meaning of parent methods

❌ **ISP Violations**:
- Large interfaces with many unrelated methods
- Classes implementing methods they don't use or need

❌ **DIP Violations**:
- High-level classes depending on concrete implementations
- Direct instantiation of dependencies inside classes
- Using `new` keyword for dependencies instead of injection

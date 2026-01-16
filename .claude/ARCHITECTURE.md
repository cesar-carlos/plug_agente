# Architecture Patterns - Magic Printer

## 🏛️ Clean Architecture + DDD

This project follows **Clean Architecture** principles combined with **Domain Driven Design (DDD)** to create a maintainable, testable, and scalable codebase.

---

## 📐 Layer Structure

```
┌─────────────────────────────────────────────────────────┐
│                   Presentation Layer                     │
│  (Pages, Widgets, Providers - UI State Management)      │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                  Application Layer                       │
│  (Services, DTOs, Mappers - Orchestration)              │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                    Domain Layer                         │
│  (Entities, Value Objects, Use Cases, Repositories)     │
│  - Pure Business Logic                                  │
│  - NO Dependencies on Other Layers                      │
└─────────────────────────────────────────────────────────┘
                            ↑
┌─────────────────────────────────────────────────────────┐
│                Infrastructure Layer                      │
│  (Data Sources, Repository Implementations, APIs)        │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 Domain Layer (Core)

### Responsibility
Pure business logic, completely independent of frameworks, UI, databases, or external services.

### Components

#### 1. Entities
Objects with identity and business logic.

```dart
// domain/entities/host.dart
class Host {
  final String id;
  final String name;
  final String address;
  final int port;
  final HostStatus status;
  final DateTime createdAt;

  const Host({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.status,
    required this.createdAt,
  });

  // Business logic
  bool get isOnline => status == HostStatus.online;
  bool get isOffline => status == HostStatus.offline;
  String get fullAddress => '$address:$port';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Host && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
```

#### 2. Value Objects
Immutable objects defined by their values, not identity.

```dart
// domain/value_objects/host_status.dart
enum HostStatus { online, offline, warning, error }

// domain/value_objects/email.dart
class Email {
  final String value;

  Email(this.value) {
    if (!Email._isValid(value)) {
      throw InvalidEmailException('Invalid email: $value');
    }
  }

  static bool _isValid(String email) {
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

#### 3. Repositories (Interfaces)
Abstract contracts for data access.

```dart
// domain/repositories/i_host_repository.dart
import 'package:result_dart/result_dart.dart';

abstract class IHostRepository {
  Future<Result<List<Host>>> getAll();
  Future<Result<Host>> getById(String id);
  Future<Result<Host>> create(Host host);
  Future<Result<void>> update(Host host);
  Future<Result<void>> delete(String id);
  Future<Result<List<Printer>>> getPrinters(String hostId);
}
```

#### 4. Use Cases
Encapsulated business operations.

```dart
// domain/use_cases/get_hosts.dart
class GetHosts {
  final IHostRepository repository;

  GetHosts(this.repository);

  Future<Result<List<Host>>> call() async {
    try {
      return await repository.getAll();
    } catch (e) {
      return Failure(ServerFailure('Failed to load hosts: ${e.toString()}'));
    }
  }
}

// domain/use_cases/connect_to_host.dart
class ConnectToHost {
  final IHostRepository repository;

  ConnectToHost(this.repository);

  Future<Result<void>> call(String hostId) async {
    if (hostId.isEmpty) {
      return Failure(ValidationFailure('Host ID is required'));
    }

    return await repository.connect(hostId);
  }
}
```

#### 5. Domain Errors
Business-specific failures.

```dart
// domain/errors/failures.dart
abstract class Failure {
  final String message;
  Failure(this.message);
}

class ServerFailure extends Failure {
  ServerFailure(String message) : super(message);
}

class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message);
}

class NetworkFailure extends Failure {
  NetworkFailure(String message) : super(message);
}

class NotFoundFailure extends Failure {
  NotFoundFailure(String message) : super(message);
}
```

### Rules
- ✅ Pure Dart only
- ✅ Can import from `core` and `shared`
- ❌ NO Flutter imports
- ❌ NO HTTP imports
- ❌ NO imports from other layers

---

## 🔧 Application Layer

### Responsibility
Orchestrates domain use cases and coordinates data flow.

### Components

#### 1. Services
Coordinate multiple use cases.

```dart
// application/services/host_service.dart
class HostService {
  final IHostRepository repository;

  HostService(this.repository);

  Future<Result<List<Host>>> getHosts() async {
    return await repository.getAll();
  }

  Future<Result<Host>> getHostById(String id) async {
    if (id.isEmpty) {
      return Failure(ValidationFailure('Host ID is required'));
    }
    return await repository.getById(id);
  }

  Future<Result<void>> connectToHost(String hostId) async {
    final hostResult = await repository.getById(hostId);

    return hostResult.fold(
      (failure) => Failure(failure),
      (host) async {
        // Business logic can go here
        return await repository.connect(hostId);
      },
    );
  }
}
```

#### 2. DTOs (Data Transfer Objects)
Transfer data between layers.

```dart
// application/dtos/host_dto.dart
class HostDTO {
  final String id;
  final String name;
  final String address;
  final int port;
  final String status;
  final DateTime createdAt;

  HostDTO({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.status,
    required this.createdAt,
  });

  // Convert from Entity
  factory HostDTO.fromEntity(Host host) {
    return HostDTO(
      id: host.id,
      name: host.name,
      address: host.address,
      port: host.port,
      status: host.status.name,
      createdAt: host.createdAt,
    );
  }

  // Convert to Entity
  Host toEntity() {
    return Host(
      id: id,
      name: name,
      address: address,
      port: port,
      status: HostStatus.values.firstWhere(
        (s) => s.name == status,
        orElse: () => HostStatus.offline,
      ),
      createdAt: createdAt,
    );
  }
}
```

### Rules
- ✅ Can import from `domain` and `core`
- ❌ NO imports from `infrastructure` or `presentation`

---

## 🌐 Infrastructure Layer

### Responsibility
Implements domain interfaces and handles external concerns.

### Components

#### 1. Data Sources
External data access implementations.

```dart
// infrastructure/datasources/host_data_source.dart
import 'package:dio/dio.dart';

class HostDataSource {
  final Dio _dio;

  HostDataSource(this._dio);

  Future<List<Map<String, dynamic>>> getAll() async {
    try {
      final response = await _dio.get('/hosts');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      throw ServerException('Failed to load hosts: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getById(String id) async {
    try {
      final response = await _dio.get('/hosts/$id');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      throw ServerException('Failed to load host: ${e.toString()}');
    }
  }
}
```

#### 2. Repository Implementations
Implement domain interfaces.

```dart
// infrastructure/repositories/host_repository.dart
class HostRepository implements IHostRepository {
  final HostDataSource dataSource;

  HostRepository(this.dataSource);

  @override
  Future<Result<List<Host>>> getAll() async {
    try {
      final data = await dataSource.getAll();
      final hosts = data.map((json) => HostModel.fromJson(json).toEntity()).toList();
      return Success(hosts);
    } on ServerException catch (e) {
      return Failure(ServerFailure(e.message));
    } catch (e) {
      return Failure(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Result<Host>> getById(String id) async {
    try {
      final data = await dataSource.getById(id);
      final host = HostModel.fromJson(data).toEntity();
      return Success(host);
    } on ServerException catch (e) {
      return Failure(ServerFailure(e.message));
    } catch (e) {
      return Failure(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }
}
```

#### 3. Models
Serialization models.

```dart
// infrastructure/models/host_model.dart
class HostModel {
  final String id;
  final String name;
  final String address;
  final int port;
  final String status;
  final String createdAt;

  HostModel({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.status,
    required this.createdAt,
  });

  factory HostModel.fromJson(Map<String, dynamic> json) {
    return HostModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      port: json['port'] as int,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'port': port,
      'status': status,
      'created_at': createdAt,
    };
  }

  Host toEntity() {
    return Host(
      id: id,
      name: name,
      address: address,
      port: port,
      status: HostStatus.values.firstWhere(
        (s) => s.name == status,
        orElse: () => HostStatus.offline,
      ),
      createdAt: DateTime.parse(createdAt),
    );
  }

  factory HostModel.fromEntity(Host host) {
    return HostModel(
      id: host.id,
      name: host.name,
      address: host.address,
      port: host.port,
      status: host.status.name,
      createdAt: host.createdAt.toIso8601String(),
    );
  }
}
```

### Rules
- ✅ Can import from `domain` and `core`
- ✅ Implements domain interfaces
- ❌ NO imports from `application` or `presentation`

---

## 🎨 Presentation Layer

### Responsibility
UI rendering and user interaction.

### Components

#### 1. Providers (State Management)
Manage UI state using Provider pattern.

```dart
// presentation/providers/host_provider.dart
class HostProvider extends ChangeNotifier {
  final GetHosts _getHosts;
  final ConnectToHost _connectToHost;

  HostProvider({
    required GetHosts getHosts,
    required ConnectToHost connectToHost,
  })  : _getHosts = getHosts,
        _connectToHost = connectToHost;

  List<HostDTO> _hosts = [];
  bool _isLoading = false;
  String? _error;

  List<HostDTO> get hosts => _hosts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadHosts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _getHosts();

    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
      },
      (hosts) {
        _hosts = hosts.map((h) => HostDTO.fromEntity(h)).toList();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> connectHost(String hostId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _connectToHost(hostId);

    result.fold(
      (failure) => _error = failure.message,
      (_) => _isLoading = false,
    );

    notifyListeners();
  }
}
```

#### 2. Pages
Application screens.

```dart
// presentation/pages/hosts_page.dart
class HostsPage extends StatelessWidget {
  const HostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HostProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: ProgressRing());
        }

        if (provider.error != null) {
          return CenteredMessage(
            icon: FluentIcons.error,
            title: 'Error',
            message: provider.error!,
          );
        }

        if (provider.hosts.isEmpty) {
          return const CenteredMessage(
            icon: FluentIcons.server,
            title: 'No Hosts',
            message: 'Add a host to get started',
          );
        }

        return ListView.builder(
          itemCount: provider.hosts.length,
          itemBuilder: (context, index) {
            final host = provider.hosts[index];
            return HostListTile(host: host);
          },
        );
      },
    );
  }
}
```

### Rules
- ✅ Can import from `domain`, `application`, and `core`
- ❌ NO imports from `infrastructure`

---

## 🔄 Data Flow Example

```
User clicks "Load Hosts" button
        ↓
[HostsPage] calls provider.loadHosts()
        ↓
[HostProvider] calls GetHosts use case
        ↓
[GetHosts] calls IHostRepository.getAll()
        ↓
[HostRepository] calls HostDataSource.getAll()
        ↓
[HostDataSource] makes HTTP request via Dio
        ↓
[HostDataSource] returns JSON
        ↓
[HostRepository] converts JSON → HostModel → Host entity
        ↓
[GetHosts] returns Result<List<Host>>
        ↓
[HostProvider] converts Host entities → HostDTOs
        ↓
[HostsPage] rebuilds UI with new data
```

---

## ✅ Architecture Checklist

Before committing code:

- [ ] Domain layer has NO Flutter/HTTP imports
- [ ] All dependencies injected via constructor
- [ ] Interfaces defined in Domain, implemented in Infrastructure
- [ ] Use cases have single responsibility (SRP)
- [ ] Result<T> used for error handling
- [ ] DTOs convert between Entity and Presentation
- [ ] Provider manages UI state only (no business logic)
- [ ] Pages/Widgets are UI only (no business logic)
- [ ] Barrel files export public APIs
- [ ] Import rules followed (no forbidden imports)

---

## 📚 Related Documents

- `PROJECT_GUIDELINES.md` - Architecture overview
- `CODING_CONVENTIONS.md` - Naming and style
- `DEPENDENCIES.md` - Standard libraries

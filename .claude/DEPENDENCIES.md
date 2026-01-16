# Standard Dependencies - Magic Printer

## 📦 Mandatory Libraries

These libraries are **STANDARD** for this project. **NEVER** use alternatives without explicit approval.

---

## 1. Navigation - `go_router`

**Version:** `^14.0.0`
**Purpose:** Declarative routing
**Location:** `core/routes/app_router.dart`

### ✅ Usage

```dart
// core/routes/app_router.dart
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/printers',
  routes: [
    GoRoute(
      path: '/printers',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/hosts/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return HostDetailsPage(hostId: id);
      },
    ),
  ],
);

// Navigate
context.go('/hosts/123');
context.push('/settings');
```

### ❌ NEVER Use

```dart
// ❌ DON'T use Navigator.push/pop directly
Navigator.push(context, MaterialPageRoute(...));

// ❌ DON'T use auto_route
// ❌ DON'T use other routing libraries
```

---

## 2. HTTP Client - `dio`

**Version:** `^5.4.0`
**Purpose:** HTTP requests
**Location:** `infrastructure/external_services/`

### ✅ Usage

```dart
// infrastructure/external_services/api_client.dart
import 'package:dio/dio.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_URL'] ?? 'http://localhost:3000',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.addAll([
      AuthInterceptor(),
      ErrorInterceptor(),
      LogInterceptor(),
    ]);
  }

  Future<Response> get(String path) => _dio.get(path);
  Future<Response> post(String path, {dynamic data}) => _dio.post(path, data: data);
}
```

### ❌ NEVER Use

```dart
// ❌ DON'T use http package
import 'package:http/http.dart' as http;

// ❌ DON'T use other HTTP libraries
```

---

## 3. Dependency Injection - `get_it`

**Version:** `^7.6.0`
**Purpose:** Service locator / DI container
**Location:** `core/di/service_locator.dart`

### ✅ Usage

```dart
// core/di/service_locator.dart
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

void setupDependencies() {
  // Data Sources
  getIt.registerLazySingleton<IHostDataSource>(
    () => HostDataSource(getIt<Dio>()),
  );

  // Repositories
  getIt.registerLazySingleton<IHostRepository>(
    () => HostRepository(getIt<IHostDataSource>()),
  );

  // Use Cases
  getIt.registerFactory(
    () => GetHosts(getIt<IHostRepository>()),
  );

  // Services
  getIt.registerLazySingleton(
    () => HostService(getIt<IHostRepository>()),
  );
}

// Usage in main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencies();
  runApp(const MyApp());
}

// Usage in code
final getHosts = getIt<GetHosts>();
```

### ❌ NEVER Use

```dart
// ❌ DON'T use Provider for DI
// ❌ DON'T use injectable
// ❌ DON'T use get_it_generator
```

---

## 4. State Management - `Provider`

**Version:** `^6.1.0`
**Purpose:** State management
**Location:** `presentation/providers/`

### ✅ Usage

```dart
// presentation/providers/host_provider.dart
import 'package:flutter/foundation.dart';

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
        _hosts = hosts;
        _isLoading = false;
      },
    );

    notifyListeners();
  }
}

// Register in main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(
      create: (_) => HostProvider(
        getHosts: getIt<GetHosts>(),
        connectToHost: getIt<ConnectToHost>(),
      ),
    ),
  ],
  child: MyApp(),
)
```

### ❌ NEVER Use

```dart
// ❌ DON'T use BLoC
// ❌ DON'T use Riverpod
// ❌ DON'T use GetX
// ❌ DON'T use MobX
```

---

## 5. Error Handling - `result_dart`

**Version:** `^2.1.1`
**Purpose:** Functional error handling
**Location:** All layers

### ✅ Usage

```dart
import 'package:result_dart/result_dart.dart';

// Domain errors
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

// Use case returns Result<T>
class GetUserById {
  final IUserRepository repository;

  GetUserById(this.repository);

  Future<Result<User>> call(String id) async {
    if (id.isEmpty) {
      return Failure(ValidationFailure('ID is required'));
    }

    return await repository.getById(id);
  }
}

// Handling Result
final result = await getUserById('123');

result.fold(
  (failure) {
    // Handle error
    print('Error: ${failure.message}');
  },
  (user) {
    // Handle success
    print('User: ${user.name}');
  },
);

// Or check first
if (result.isSuccess()) {
  final user = result.getOrNull();
} else {
  final error = result.exceptionOrNull();
}
```

### ❌ NEVER Use

```dart
// ❌ DON'T use Either from dartz
// ❌ DON'T use exceptions for flow control
// ❌ DON'T use custom Result implementations
```

---

## 6. UUID Generation - `uuid`

**Version:** `^4.3.0`
**Purpose:** Generate unique IDs
**Location:** Domain entities

### ✅ Usage

```dart
import 'package:uuid/uuid.dart';

const uuid = Uuid();

// Domain entities
class Host {
  final String id;
  final String name;

  Host({
    String? id,
    required this.name,
  }) : id = id ?? uuid.v4();
}

// Generate UUID
final newId = uuid.v4();
```

---

## 7. Environment Variables - `flutter_dotenv`

**Version:** `^5.1.0`
**Purpose:** Load environment variables
**Location:** `.env` file

### ✅ Usage

```dart
// .env file
API_URL=http://localhost:3000
API_KEY=your_api_key_here
DEFAULT_PORT=8080

// main.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

// Usage anywhere
final apiUrl = dotenv.env['API_URL'] ?? 'http://localhost:3000';
final apiKey = dotenv.env['API_KEY'] ?? '';
final port = int.tryParse(dotenv.env['DEFAULT_PORT'] ?? '') ?? 8080;
```

---

## 8. Desktop UI - `fluent_ui`

**Version:** `^4.0.0`
**Purpose:** Windows Fluent Design UI
**Location:** All presentation widgets

### ✅ Usage

```dart
import 'package:fluent_ui/fluent_ui.dart';

class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(title: Text('My Page')),
      content: ListView.builder(
        itemBuilder: (context, index) {
          return ListTile(
            title: Text('Item $index'),
            onPressed: () => print('Pressed'),
          );
        },
      ),
    );
  }
}
```

---

## 📋 Dependency Checklist

When adding new functionality:

- [ ] Routes configured with `go_router` in `core/routes/`
- [ ] HTTP calls use `dio` in `infrastructure/external_services/`
- [ ] Dependencies registered in `get_it` in `core/di/`
- [ ] State managed with `Provider` in `presentation/providers/`
- [ ] Errors handled with `Result<T>` from `result_dart`
- [ ] UUIDs generated with `uuid` package
- [ ] Environment vars in `.env` loaded with `flutter_dotenv`
- [ ] UI uses `fluent_ui` widgets

---

## 🚫 Forbidden Alternatives

| Standard | ❌ NEVER Use |
|----------|--------------|
| go_router | Navigator, auto_route, router_gen |
| dio | http package, graphql_flutter |
| get_it | Provider for DI, injectable, get_it_generator |
| Provider | BLoC, Riverpod, GetX, MobX |
| result_dart | Either (dartz), custom Result |
| uuid | DateTime.millisecondsSinceEpoch, random.uuid |

---

## 📚 Related Documents

- `PROJECT_GUIDELINES.md` - Architecture overview
- `CODING_CONVENTIONS.md` - Naming and style
- `ARCHITECTURE.md` - Layer structure and patterns

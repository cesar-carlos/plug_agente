# result_dart - Guia de Estilo

**Based on**: [result_dart package](https://pub.dev/packages/result_dart) and Clean Architecture principles

## Visão Geral

O projeto usa `result_dart` (versão ^2.1.1) para tratamento de erros de forma tipada, seguindo o padrão `Result<T, Failure>`.

```dart
import 'package:result_dart/result_dart.dart';

// Success path
return Success(data);

// Failure path
return Failure(ValidationFailure('Invalid input'));

// Consuming
result.fold(
  (data) => print('Success: $data'),
  (failure) => print('Error: ${failure.message}'),
);
```

## Padrões por Camada

### 1. Domain Layer (Entities, Value Objects, Use Cases)

**Responsabilidade**: Definir tipos de erro e retornar `Result` sem try/catch

```dart
// ✅ Use Case - Sempre retorna Result, sem try/catch
Future<Result<User>> call(String id) async {
  // Validação retorna Failure
  if (id.isEmpty) {
    return Failure(ValidationFailure('ID cannot be empty'));
  }

  // Delega para repository, propagando Result
  return _repository.getById(id);
}
```

**Regras**:
- ✅ Use cases **nunca** fazem try/catch
- ✅ Retornam `Result<T>` para operações que podem falhar
- ✅ Usam validações de domínio e retornam `ValidationFailure`
- ❌ **Nunca** lançam exceções (exceto em casos de programação incorreta)

### 2. Application Layer (Services)

**Responsabilidade**: Orquestrar use cases e services, com try/catch apenas em I/O

```dart
// ✅ Service - Try/catch apenas em fronteiras de I/O
Future<Result<void>> saveConfig(Config config) async {
  final result = await _repository.getCurrentConfig();

  return result.fold(
    (current) async {
      // Try/catch apenas na operação de I/O
      try {
        final updated = current.copyWith(data: config.data);
        return await _repository.save(updated);
      } on Exception catch (e, stackTrace) {
        AppLogger.error('Failed to save config', e, stackTrace);
        return Failure(DatabaseFailure('Failed to save: $e'));
      }
    },
    (failure) => Failure(failure),
  );
}
```

**Regras**:
- ✅ Try/catch **apenas** em operações de I/O (rede, disco, banco)
- ✅ Logging estruturado com stack trace
- ✅ Propaga `Result` de use cases sem wrapping desnecessário
- ❌ **Não** faça try/catch em volta de chamadas a use cases

### 3. Infrastructure Layer (Repositories, Clients, Gateways)

**Responsabilidade**: Capturar exceções externas e converter para `Result<Failure>`

```dart
// ✅ Repository - Captura exceções de I/O
@override
Future<Result<User>> getById(String id) async {
  try {
    final model = await _dataSource.getById(id);
    return Success(model.toEntity());
  } on SocketException catch (e, stackTrace) {
    return Failure(
      FailureConverter.convert(e, stackTrace, operation: 'getById'),
    );
  } on Exception catch (e, stackTrace) {
    return Failure(
      FailureConverter.convert(e, stackTrace, operation: 'getById'),
    );
  }
}
```

**Regras**:
- ✅ Sempre capturar exceções em fronteiras de I/O
- ✅ Usar `FailureConverter.convert()` para conversão padronizada
- ✅ Preservar stack trace para debugging
- ✅ Retornar `Result<T>` com tipos de falha específicos

### 4. Presentation Layer (Providers, Controllers)

**Responsabilidade**: Consumir `Result` e atualizar UI - **SEM try/catch**

```dart
// ✅ Provider - Sem try/catch, apenas consome Result
Future<void> loadData() async {
  _isLoading = true;
  _error = '';
  notifyListeners();

  final result = await _loadDataUseCase();

  result.fold(
    (data) {
      _data = data;
    },
    (failure) {
      _error = failure.toUserMessage();
      AppLogger.error('Failed to load: $_error');
    },
  );

  _isLoading = false;
  notifyListeners();
}
```

**Regras**:
- ✅ **Nunca** faça try/catch em volta de chamadas a use cases
- ✅ Use `toUserMessage()` extension para mensagens ao usuário
- ✅ Log erros com contexto adequado
- ❌ **Não** mascare bugs com "Unexpected error"

## Imports e Conflitos de Nomes

### Problema

`result_dart` exporta `Failure` como classe, e nosso domínio também tem `Failure`. Isso causa conflito.

### Solução: Alias para Domain Failures

```dart
// ✅ CORRETO - Usa alias para evitar conflito
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

// Criando failure do domínio
return Failure(domain_errors.ValidationFailure('message'));

// Consumindo Result com Failure
result.fold(
  (data) => _data = data,
  (failure) => _error = failure.toUserMessage(),
);
```

### Imports por Camada

**Presentation**:
```dart
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';
```

**Application**:
```dart
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';
```

**Infrastructure**:
```dart
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/errors/failure_converter.dart';
import 'package:result_dart/result_dart.dart';
```

## Extensions e Helpers

### toUserMessage()

Use sempre `toUserMessage()` para mensagens ao usuário:

```dart
// ✅ CORRETO
_error = failure.toUserMessage();
AppLogger.error('Operation failed: ${failure.toUserMessage()}');

// ❌ EVITAR
final message = failure is Failure ? failure.message : failure.toString();
_error = message;
```

### FailureConverter

Use `FailureConverter.convert()` em fronteiras de I/O:

```dart
// ✅ CORRETO
} on Exception catch (e, stackTrace) {
  return Failure(
    FailureConverter.convert(
      e,
      stackTrace,
      operation: 'saveConfig',
      additionalContext: {'configId': config.id},
    ),
  );
}
```

## Result<void> e Success(unit)

Para métodos que não retornam dados, use `Result<void>` e `Success(unit)`:

```dart
// ✅ CORRETO
Future<Result<void>> save(Config config) async {
  try {
    await _repository.save(config);
    return const Success(unit);
  } on Exception catch (e, stackTrace) {
    return Failure(DatabaseFailure('Failed to save: $e'));
  }
}

// ❌ EVITAR
Future<Result<Object>> save(Config config) async {
  await _repository.save(config);
  return Success(Object());
}
```

## Try/Catch: Quando Usar

### ✅ USE Try/Catch Em:

1. **Fronteiras de I/O**: Rede, disco, banco de dados
2. **APIs externas**: HTTP clients, bibliotecas de terceiros
3. **Operações de SO**: Windows APIs, system calls
4. **Event callbacks**: Onde erros não devem quebrar o fluxo

### ❌ NÃO USE Try/Catch Em:

1. **Métodos que retornam Result**: Use cases, services, repositories
2. **Código de orquestração**: Deixe bugs subirem para debugging
3. **Lógica de negócio**: Use validação e retorne Failure
4. **UI code**: Deixe exceções de UI serem tratadas pelo framework

## Async Await com Result

Padrão correto para async/await com Result:

```dart
// ✅ CORRETO - Chama e aguarda Result
final result = await _useCase(params);
result.fold(
  (data) => _processData(data),
  (failure) => _handleError(failure),
);

// ❌ EVITAR - Desnecessário async/await quando retorna direto
Future<Result<Data>> getData() async {
  final result = await _repository.getData();
  return result; // Desnecessário
}

// ✅ MELHOR - Retorna diretamente
Future<Result<Data>> getData() => _repository.getData();
```

## Aninhamento de Result

Para evitar aninhamento profundo, use flatMap ou encadeamento:

```dart
// ❌ EVITAR - Aninhamento profundo
final result1 = await _step1();
return result1.fold(
  (data1) async {
    final result2 = await _step2(data1);
    return result2.fold(
      (data2) async {
        final result3 = await _step3(data2);
        return result3;
      },
      (failure) => Failure(failure),
    );
  },
  (failure) => Failure(failure),
);

// ✅ MELHOR - Use early returns
final result1 = await _step1();
if (result1.isFailure()) return result1;

final data1 = (result1 as Success).value;
final result2 = await _step2(data1);
if (result2.isFailure()) return result2;

final data2 = (result2 as Success).value;
return await _step3(data2);
```

## Testes com Result

### Testando Success Path

```dart
test('should return user when repository succeeds', () async {
  // Arrange
  final user = User(id: '123', name: 'John');
  when(() => mockRepository.getById('123'))
      .thenAnswer((_) async => Success(user));

  // Act
  final result = await useCase('123');

  // Assert
  expect(result.isSuccess(), isTrue);
  result.fold(
    (user) => expect(user.name, equals('John')),
    (failure) => fail('Should not return failure'),
  );
});
```

### Testando Failure Path

```dart
test('should return ValidationFailure when id is empty', () async {
  // Act
  final result = await useCase('');

  // Assert
  expect(result.isFailure(), isTrue);
  result.fold(
    (user) => fail('Should not return user'),
    (failure) => expect(failure, isA<ValidationFailure>()),
  );
});
```

## Checklist

Ao usar `result_dart`:

- [ ] **Domain**: Use cases retornam `Result<T>` sem try/catch
- [ ] **Application**: Services usam try/catch apenas em I/O
- [ ] **Infrastructure**: Repositories capturam exceções e retornam Result
- [ ] **Presentation**: Providers consomem Result sem try/catch
- [ ] Use `toUserMessage()` para mensagens ao usuário
- [ ] Use `FailureConverter.convert()` em fronteiras de I/O
- [ ] Use alias `domain_errors` para evitar conflitos de nomes
- [ ] Use `const Success(unit)` para `Result<void>`
- [ ] Log erros com stack trace em catch blocks
- [ ] Tests cobrem ambos paths (success e failure)

## Referências

- [result_dart package](https://pub.dev/packages/result_dart)
- [Effective Dart: Error Handling](https://dart.dev/guides/libraries/create-library-packages#error-handling)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)

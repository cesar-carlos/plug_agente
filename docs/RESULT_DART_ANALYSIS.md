# Análise do Uso do result_dart

## Status Atual

O projeto utiliza o pacote `result_dart` (versão ^2.1.1) para tratamento de erros de forma tipada, seguindo o padrão `Result<T, Failure>` (ou `Result<T>` com Failure implícito).

## ✅ IMPLEMENTAÇÃO CONCLUÍDA (Janeiro 2026)

Todas as melhorias de prioridade ALTA e MÉDIA foram implementadas com sucesso.

### Mudanças Implementadas

**Presentation Layer (Providers)**:
- ✅ `auth_provider.dart` - Removidos 2 try/catch redundantes
- ✅ `connection_provider.dart` - Removidos 4 try/catch redundantes
- ✅ `config_provider.dart` - Removidos 3 try/catch redundantes
- ✅ `notification_provider.dart` - Já estava correto
- ✅ `playground_provider.dart` - Padrão Result aplicado corretamente

**Application Layer (Services)**:
- ✅ `auth_service.dart` - Try/catch largo refatorado para try/catch específico em I/O
- ✅ `connection_service.dart` - Removidos 2 try/catch redundantes

**Extensões e Utilitários**:
- ✅ `toUserMessage()` extension aplicado consistentemente
- ✅ Conflitos de nomes entre `Failure` (domínio) e `Failure` (result_dart) resolvidos
- ✅ Logging estruturado adicionado com preservação de stack trace

### Resultado da Refatoração

```
Antes:
- 13 blocos try/catch em providers
- 4+ blocos redundantes mascarando bugs
- Código inconsistente com mistura de patterns

Depois:
- 9 blocos try/catch (todos justificados em callbacks de evento ou I/O)
- 0 blocos redundantes em métodos que chamam use cases
- Padrão Result aplicado consistentemente
- Bugs de código não são mais mascarados como "erros inesperados"

Análise estática:
- ✅ 2 issues (info-level, não-críticos)
- ✅ 186 arquivos formatados
- ✅ 0 erros
```

## Problemas Identificados (Original)

> **Nota**: Esta seção documenta os problemas originais que foram identificados e já foram corrigidos.

### 1. Try/Catch Redundantes nos Providers (Presentation Layer)

**Localização**: `lib/presentation/providers/*.dart`

**Problema**: Os providers estão fazendo try/catch desnecessário em volta de chamadas que já retornam `Result`.

```dart
// ❌ PROBLEMA: auth_provider.dart (linhas 60-64)
try {
  final result = await _loginUseCase(serverUrl, credentials);

  result.fold(
    (token) async { /* ... */ },
    (failure) {
      _status = AuthStatus.error;
      _error = failure.toUserMessage();
    },
  );
} on Exception catch (e) {
  // REDUNDANTE: Se o use case lançar exceção, é um BUG no código
  _status = AuthStatus.error;
  _error = 'Unexpected error: $e';
}
```

**Por que é redundante?**
- O use case já retorna `Result<AuthToken, Failure>`
- Se o use case lançar uma exceção, isso indica um **bug no código**, não um erro esperado
- A exceção nunca deveria ser lançada se o use case estiver corretamente implementado
- O try/catch está "mascarando" bugs que deveriam ser tratados no use case

**Exemplo CORRETO**: `playground_provider.dart` (linhas 50-87)
```dart
// ✅ CORRETO: Sem try/catch, trabalha diretamente com Result
Future<void> executeQuery() async {
  _clearError();
  _isLoading = true;
  notifyListeners();

  final stopwatch = Stopwatch()..start();
  final result = await _executePlaygroundQuery(_query);
  stopwatch.stop();

  _isLoading = false;

  result.fold(
    (response) { /* ... */ },
    (failure) {
      _error = failure.toUserMessage();
      AppLogger.error('Failed to execute query: ${_error ?? failure}');
    },
  );

  notifyListeners();
}
```

**Arquivos afetados**:
- `auth_provider.dart` - 2 try/catch redundantes
- `notification_provider.dart` - 0 try/catch (já está correto)
- `playground_provider.dart` - 1 try/catch apenas em método TODO (streaming)

### 2. Mix de Result e Exception em Services

**Localização**: `lib/application/services/*.dart`

**Problema**: Alguns services retornam `Result` corretamente, mas ainda usam try/catch internamente de forma inconsistente.

```dart
// ❌ INCONSISTENTE: auth_service.dart (linhas 59-61)
Future<Result<void>> saveAuthToken(AuthToken token) async {
  try {
    final configResult = await _configRepository.getCurrentConfig();

    return await configResult.fold(
      (config) async { /* ... */ },
      (failure) async { /* ... */ },
    );
  } on Exception catch (e) {
    // A conversão para Failure deveria ser feita MAS o try/catch
    // captura exceções que podem ser bugs no código acima
    return Failure(DatabaseFailure('Failed to save auth token: $e'));
  }
}
```

**Por que é problemático?**
- Se o código dentro do try/catch tiver um bug (ex: null pointer), ele será convertido em `DatabaseFailure`
- Isso torna debugging difícil, pois erros de programação viram "erros de banco de dados"
- O try/catch está muito "largo" - captura tudo, inclusive exceções não relacionadas

**Solução**: Use try/catch apenas em **fronteiras de I/O** (rede, disco, banco).

```dart
// ✅ MELHOR: Try/catch apenas na fronteira de I/O
Future<Result<void>> saveAuthToken(AuthToken token) async {
  final configResult = await _configRepository.getCurrentConfig();

  return configResult.fold(
    (config) async {
      // Try/catch aqui está OK - é operação de I/O com repositório
      try {
        final updatedConfig = config.copyWith(
          authToken: token.token,
          refreshToken: token.refreshToken,
          updatedAt: DateTime.now(),
        );
        final saveResult = await _configRepository.save(updatedConfig);
        return saveResult.fold(
          (_) => const Success(unit),
          (failure) => Failure(failure),
        );
      } on Exception catch (e, stackTrace) {
        return Failure(
          FailureConverter.convert(e, stackTrace, operation: 'saveAuthToken'),
        );
      }
    },
    (failure) => Failure(NotFoundFailure('No configuration found')),
  );
}
```

### 3. Serviços de Infraestrutura com Try/Catch Justificados

**Localização**:
- `lib/core/services/tray_manager_service.dart`
- `lib/core/services/window_manager_service.dart`

**Status**: ✅ **CORRETO** - Try/catch são justificados aqui

**Por que estão corretos?**
- São operações de **sistema operacional** (Windows tray, window manager)
- Integram com APIs externas que não seguem o padrão `Result`
- Podem falhar de maneiras inesperadas que não estão sob nosso controle
- Não faz parte da lógica de negócio core

```dart
// ✅ CORRETO: Operações de sistema operacional
try {
  final iconPath = await _getTrayIconPath();
  final iconFile = File(iconPath);
  if (iconFile.existsSync()) {
    await trayManager.setIcon(iconFile.absolute.path);
  } else {
    final executablePath = Platform.resolvedExecutable;
    await trayManager.setIcon(executablePath);
  }
} on Exception catch (e, stackTrace) {
  _logger.e('Erro ao configurar ícone da bandeja', error: e, stackTrace: stackTrace);
  // Fallback para executável
  try {
    final executablePath = Platform.resolvedExecutable;
    await trayManager.setIcon(executablePath);
  } on Exception catch (e2) {
    _logger.e('Erro crítico ao configurar ícone', error: e2);
  }
}
```

### 4. Conversão Inconsistente de Exception → Failure

**Problema**: Alguns lugares fazem conversão manual de exceptions para strings, outros usam `FailureConverter`.

```dart
// ❌ INCONSISTENTE: Conversão manual
final failureMessage = failure is Failure
    ? failure.message
    : failure.toString();
_error = 'Failed to save token: $failureMessage';

// ✅ CONSISTENTE: Usar extension
_error = failure.toUserMessage();
```

**Solução**: A extensão `toUserMessage()` já existe em `failure_extensions.dart` e deve ser usada sempre.

## Padrões Recomendados

### Camada de Infraestrutura (implementa interfaces do Domain)

**Responsabilidade**: Capturar exceções de I/O e converter para `Result<Failure>`

```dart
@override
Future<Result<AuthToken>> login(String serverUrl, AuthCredentials credentials) async {
  try {
    final response = await _dio.post<Map<String, dynamic>>(url, data: {...});

    if (response.statusCode == 200 && data['success'] == true) {
      return Success(AuthToken(token: token, refreshToken: refreshToken));
    }

    return Failure(ValidationFailure(data['error'] ?? 'Login failed'));
  } on DioException catch (e, stackTrace) {
    // Capturar exceções específicas da lib HTTP
    return Failure(FailureConverter.convert(e, stackTrace, operation: 'login'));
  } on Exception catch (e, stackTrace) {
    // Capturar outras exceções inesperadas
    return Failure(FailureConverter.convert(e, stackTrace, operation: 'login'));
  }
}
```

### Camada de Aplicação (Services e Use Cases)

**Responsabilidade**: Orquestrar chamadas e propagar `Result` sem try/catch adicional

```dart
// ✅ Use Case - Sem try/catch
Future<Result<AuthToken>> call(String serverUrl, AuthCredentials credentials) async {
  if (serverUrl.isEmpty) {
    return Failure(ValidationFailure('Server URL cannot be empty'));
  }

  if (!credentials.isValid) {
    return Failure(ValidationFailure('Username and password are required'));
  }

  // Apenas delega para o service - sem try/catch
  return _service.login(serverUrl, credentials);
}

// ✅ Service - Try/catch apenas se necessário para orquestração complexa
Future<Result<void>> saveAuthToken(AuthToken token) async {
  final configResult = await _configRepository.getCurrentConfig();

  return configResult.fold(
    (config) async {
      try {
        // Operação de I/O com repositório
        final updatedConfig = config.copyWith(...);
        return await _configRepository.save(updatedConfig);
      } on Exception catch (e, stackTrace) {
        // Converter exceção de I/O para Failure
        return Failure(FailureConverter.convert(e, stackTrace, operation: 'save'));
      }
    },
    (failure) => Failure(NotFoundFailure('No configuration found')),
  );
}
```

### Camada de Apresentação (Providers)

**Responsabilidade**: Consumir `Result` e atualizar UI - **SEM try/catch**

```dart
// ✅ CORRETO: Provider sem try/catch
Future<void> login(String serverUrl, AuthCredentials credentials) async {
  _status = AuthStatus.authenticating;
  _error = '';
  notifyListeners();

  final result = await _loginUseCase(serverUrl, credentials);

  result.fold(
    (token) async {
      _currentToken = token;
      final saveResult = await _saveUseCase(token);
      saveResult.fold(
        (_) {
          _status = AuthStatus.authenticated;
          AppLogger.info('Login successful');
        },
        (failure) {
          _status = AuthStatus.error;
          _error = 'Failed to save token: ${failure.toUserMessage()}';
          AppLogger.error('Failed to save token: ${failure.toUserMessage()}');
        },
      );
    },
    (failure) {
      _status = AuthStatus.error;
      _error = failure.toUserMessage();
      AppLogger.error('Login failed: $_error');
    },
  );

  notifyListeners();
}
```

## Resumo de Problemas por Arquivo

| Arquivo | Problema | Severidade | Ação Recomendada |
|---------|----------|------------|------------------|
| `auth_provider.dart` | Try/catch redundante (linhas 60-64, 108-112) | Alta | Remover try/catch |
| `notification_provider.dart` | ✅ Sem problemas | - | Manter como está |
| `playground_provider.dart` | ⚠️ Try/catch em método TODO (linhas 131-148) | Baixa | Remover quando implementar streaming |
| `auth_service.dart` | Try/catch muito largo (linhas 28-61) | Média | Refatorar para try/catch mais específico |
| `connection_service.dart` | Possíveis try/catch largos | Média | Analisar caso a caso |
| `tray_manager_service.dart` | ✅ Sem problemas (operações de SO) | - | Manter como está |
| `window_manager_service.dart` | ✅ Sem problemas (operações de SO) | - | Manter como está |

## Estatísticas

```
Total de arquivos analisados: 20+
Arquivos com try/catch redundante: 3
Arquivos com try/catch justificado: 2
Arquivos seguindo padrão Result corretamente: 15+

Blocos try/catch em providers: 13
Blocos try/catch que devem ser removidos: ~4
Blocos try/catch que devem ser mantidos: ~9
```

## Benefícios da Refatoração

1. **Código mais limpo**: Menos nested blocks
2. **Debugging mais fácil**: Bugs não são mascarados como falhas de negócio
3. **Consistência**: Padrão Result aplicado uniformemente
4. **Type safety**: Erros são parte do tipo, não exceções inesperadas
5. **Testabilidade**: Mais fácil testar caminhos de erro

## Próximos Passos

1. ✅ **Prioridade Alta**: Remover try/catch redundantes dos providers
2. ✅ **Prioridade Média**: Refatorar services para try/catch mais específicos
3. ⏳ **Prioridade Baixa**: Documentar padrões em guia de estilo
4. ⏳ **Validação**: Criar testes para garantir que exceções não são perdidas

---

# Padrões Finais Implementados

## Conflitos de Nomes: Failure (domínio) vs Failure (result_dart)

### Problema

O pacote `result_dart` exporta `Failure` como uma classe, e nosso domínio também tem `Failure` como classe base. Isso causa conflito de nomes quando ambos são importados.

### Solução Implementada

Usar alias para import de failures do domínio:

```dart
// ❌ Causa conflito
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:result_dart/result_dart.dart';

// ✅ Correto - usa alias
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

// Uso:
return Failure(domain_errors.ValidationFailure('message'));
```

### Padrão de Imports em Cada Camada

**Presentation (Providers)**:
```dart
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

// Usa toUserMessage() extension
_error = failure.toUserMessage();
```

**Application (Services)**:
```dart
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

// Cria failures com alias quando necessário
return Failure(domain_errors.DatabaseFailure('message'));
```

**Infrastructure (Clients/Gateways)**:
```dart
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/errors/failure_converter.dart';
import 'package:result_dart/result_dart.dart';

// Usa FailureConverter e extensions
return Failure(FailureConverter.convert(e, stackTrace, operation: 'login'));
```

## Use de toUserMessage()

A extensão `toUserMessage()` está disponível em `failure_extensions.dart` e deve ser usada consistentemente para converter failures em mensagens para o usuário.

```dart
// ✅ CORRETO - Usa extensão
_error = failure.toUserMessage();
AppLogger.error('Operation failed: ${failure.toUserMessage()}');

// ❌ EVITAR - Conversão manual
final message = failure is Failure ? failure.message : failure.toString();
_error = message;
```

## Try/Catch: Quando Usar

### ✅ USE Try/Catch Em:

1. **Fronteiras de I/O** (rede, disco, banco de dados)
2. **Operações de sistema operacional** (APIs externas)
3. **Callbacks de evento** (onde erros não devem quebrar o fluxo)

### ❌ NÃO USE Try/Catch Em:

1. **Métodos que já retornam Result** (use cases, services, repositories)
2. **Código de orquestração** (deixe exceções de bugs subirem)
3. **Lógica de negócio** (use validação e retorne Failure)

## Exemplo Completo: Provider Correto

```dart
class AuthProvider extends ChangeNotifier {
  Future<void> login(String serverUrl, AuthCredentials credentials) async {
    _status = AuthStatus.authenticating;
    _error = '';
    notifyListeners();

    // SEM try/catch - use case já retorna Result
    final result = await _loginUseCase(serverUrl, credentials);

    result.fold(
      (token) async {
        _currentToken = token;
        final saveResult = await _saveUseCase(token);
        saveResult.fold(
          (_) {
            _status = AuthStatus.authenticated;
            AppLogger.info('Login successful');
          },
          (failure) {
            _status = AuthStatus.error;
            _error = 'Failed to save token: ${failure.toUserMessage()}';
            AppLogger.error('Failed to save token: ${failure.toUserMessage()}');
          },
        );
      },
      (failure) {
        _status = AuthStatus.error;
        _error = failure.toUserMessage();
        AppLogger.error('Login failed: $_error');
      },
    );

    notifyListeners();
  }
}
```

## Logging Estruturado

Sempre que capturar uma exceção em fronteiras de I/O, use logging estruturado com stack trace:

```dart
try {
  final result = await _repository.save(config);
  return result.fold(
    (_) => const Success(unit),
    (failure) => Failure(failure),
  );
} on Exception catch (e, stackTrace) {
  AppLogger.error(
    'Exception saving config to repository',
    e,
    stackTrace,
  );
  return Failure(DatabaseFailure('Failed to save config: ${e.toString()}'));
}
```

## Checklist de Code Review

Ao revisar código com tratamento de erros:

- [ ] Providers não têm try/catch em volta de chamadas a use cases
- [ ] Services usam try/catch apenas em fronteiras de I/O
- [ ] Use cases não têm try/catch (apenas validação + return Failure)
- [ ] `toUserMessage()` é usado para mensagens ao usuário
- [ ] Conflitos de nomes resolvidos com alias `domain_errors`
- [ ] Logging estruturado com stack trace em catch blocks
- [ ] Infraestrutura usa `FailureConverter.convert()` consistentemente

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/command_line_context_template_resolver.dart';

void main() {
  const resolver = CommandLineContextTemplateResolver();

  test('replaces exactly one context placeholder only after canonical validation', () {
    final result = resolver.resolve(
      actionId: 'action-1',
      command: r'tool --context ${context_path}',
      injectionMode: AgentActionContextInjectionMode.argument,
      validatedContextPath: r'C:\safe path\context.json',
    );
    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow(), r'tool --context "C:\safe path\context.json"');
  });

  test('rejects implicit legacy context and duplicate placeholders', () {
    final legacy = resolver.resolve(
      actionId: 'action-1',
      command: 'tool',
      injectionMode: AgentActionContextInjectionMode.argument,
      validatedContextPath: r'C:\context.json',
    );
    final duplicate = resolver.resolve(
      actionId: 'action-1',
      command: r'tool ${context_path} ${context_path}',
      injectionMode: AgentActionContextInjectionMode.file,
      validatedContextPath: r'C:\context.json',
    );
    expect(legacy.isError(), isTrue);
    expect(duplicate.isError(), isTrue);
  });

  test('rejects placeholder without a context file', () {
    final result = resolver.resolve(
      actionId: 'action-1',
      command: r'tool ${context_path}',
      injectionMode: AgentActionContextInjectionMode.argument,
      validatedContextPath: null,
    );
    expect(result.isError(), isTrue);
  });

  test('always quotes context paths so cmd metacharacters remain data', () {
    final result = resolver.resolve(
      actionId: 'action-1',
      command: r'tool ${context_path}',
      injectionMode: AgentActionContextInjectionMode.argument,
      validatedContextPath: r'C:\safe&literal\context.json',
    );
    expect(result.getOrThrow(), r'tool "C:\safe&literal\context.json"');
  });
}

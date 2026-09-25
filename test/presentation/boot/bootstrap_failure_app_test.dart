import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/presentation/boot/bootstrap_failure_app.dart';

void main() {
  testWidgets('should show startup failure modal with guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      BootstrapFailureApp(
        error: const GlobalStorageBootstrapException(
          attempts: <String>[r'C:\ProgramData\PlugAgente -> Access denied'],
        ),
        stackTrace: StackTrace.fromString('trace line'),
        revealNativeWindow: () async {},
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Falha na inicialização'), findsOneWidget);
    expect(
      find.textContaining('Execute o Plug Agente como administrador'),
      findsOneWidget,
    );
    expect(find.text('Detalhes técnicos:'), findsOneWidget);
    expect(find.textContaining('trace line'), findsOneWidget);
    expect(find.text('Fechar aplicativo'), findsOneWidget);
  });

  testWidgets('should reveal the hidden native window before showing the modal', (
    tester,
  ) async {
    var revealCalls = 0;

    await tester.pumpWidget(
      BootstrapFailureApp(
        error: StateError('boom'),
        revealNativeWindow: () async {
          revealCalls++;
        },
      ),
    );

    await tester.pumpAndSettle();

    expect(revealCalls, 1);
    expect(find.text('Falha na inicialização'), findsOneWidget);
  });

  testWidgets('should still show the modal when revealing the native window fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      BootstrapFailureApp(
        error: StateError('boom'),
        revealNativeWindow: () async {
          throw StateError('show_window_failed');
        },
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Falha na inicialização'), findsOneWidget);
  });
}

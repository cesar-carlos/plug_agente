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
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Falha na inicializacao'), findsOneWidget);
    expect(
      find.textContaining('Execute o Plug Agente como administrador'),
      findsOneWidget,
    );
    expect(find.text('Detalhes tecnicos:'), findsOneWidget);
    expect(find.textContaining('trace line'), findsOneWidget);
    expect(find.text('Fechar aplicativo'), findsOneWidget);
  });
}

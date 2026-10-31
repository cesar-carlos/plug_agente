import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_export_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_io_download.dart';
import 'package:result_dart/result_dart.dart';

Widget _app(Widget child) => FluentApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: ScaffoldPage(content: child),
);

void main() {
  testWidgets('keyboard confirms the selected stream and cancels without exporting', (tester) async {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _DirectoryPicker();
    addTearDown(() => FilePickerPlatform.instance = previous);
    final exports = <(ActionIoStream, String)>[];
    await tester.pumpWidget(
      _app(
        AgentActionIoDownload(
          enabled: true,
          onExport: (stream, path) async {
            exports.add((stream, path));
            return const Success(ActionIoExportSummary(bytes: 0, outputComplete: true, terminal: true));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tabTo(tester, find.widgetWithText(Button, 'Download stderr'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(exports, isEmpty);
    expect(tester.widget<TextBox>(find.byType(TextBox)).controller!.text, 'stderr.bin');
    await _tabTo(tester, find.widgetWithText(FilledButton, 'Save file'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(exports, [(ActionIoStream.stderr, p.join('fixture', 'stderr.bin'))]);
    await _tabTo(tester, find.widgetWithText(Button, 'Download stdout'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _tabTo(tester, find.widgetWithText(Button, 'Cancel'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(exports, hasLength(1));
    expect(find.byType(ContentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('destination confirmation labels the file operation rather than action editing', (tester) async {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _DirectoryPicker();
    addTearDown(() => FilePickerPlatform.instance = previous);
    await tester.pumpWidget(
      _app(
        AgentActionIoDownload(
          enabled: true,
          onExport: (_, _) async =>
              const Success(ActionIoExportSummary(bytes: 0, outputComplete: true, terminal: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download stdout'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(FilledButton, 'Save file'), findsOneWidget);
    expect(find.text('Save action'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets('downloads the selected stream once and reports incomplete capture', (tester) async {
    final pending = Completer<Result<ActionIoExportSummary>>();
    final calls = <ActionIoStream>[];
    await tester.pumpWidget(
      _app(
        AgentActionIoDownload(
          enabled: true,
          pickDestination: (_, stream) async {
            expect(stream, ActionIoStream.stderr);
            return r'C:\fixture\stderr.bin';
          },
          onExport: (stream, path) {
            expect(path, r'C:\fixture\stderr.bin');
            calls.add(stream);
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Download stderr'));
    await tester.pump();
    expect(calls, [ActionIoStream.stderr]);
    expect(tester.widget<Button>(find.widgetWithText(Button, 'Download stdout')).onPressed, isNull);
    pending.complete(const Success(ActionIoExportSummary(bytes: 3, outputComplete: false, terminal: true)));
    await tester.pumpAndSettle();
    expect(find.text('A partial output was saved. This file does not represent a complete capture.'), findsOneWidget);
    expect(find.byType(ProgressRing), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling destination selection never exports', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        AgentActionIoDownload(
          enabled: true,
          pickDestination: (_, _) async => null,
          onExport: (_, _) async {
            calls++;
            return const Success(ActionIoExportSummary(bytes: 0, outputComplete: true, terminal: true));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download stdout'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(ProgressRing), findsNothing);
  });
}

class _DirectoryPicker extends FilePickerPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => 'fixture';
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  bool hasFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final element = target.evaluate().single;
    var found = identical(context, element);
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) found = true;
      return !found;
    });
    return found;
  }

  for (var attempt = 0; attempt < 20 && !hasFocus(); attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(hasFocus(), isTrue, reason: 'Control must be reachable through keyboard traversal.');
}

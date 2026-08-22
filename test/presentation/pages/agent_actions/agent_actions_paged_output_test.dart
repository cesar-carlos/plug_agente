import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_paged_output.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('does not reset visible text when only the slice callback identity changes', (tester) async {
    var sliceCalls = 0;

    Widget buildOutput({required Object pagingIdentity}) {
      return FluentApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: AgentActionPagedCapturedOutput(
            label: 'stdout',
            loadMoreLabel: 'load more',
            storageTruncated: false,
            storedInChunks: true,
            pagingIdentity: pagingIdentity,
            l10n: l10n,
            onSlice: (offset, maxBytes) async {
              sliceCalls += 1;
              return Success((
                text: 'page-$sliceCalls',
                nextOffset: offset + 8,
                totalBytes: 16,
                responseTruncated: true,
                effectiveStart: offset,
              ));
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(buildOutput(pagingIdentity: 'exec-1:stdout'));
    await tester.pump();
    await tester.pump();

    expect(find.text('page-1'), findsOneWidget);
    expect(sliceCalls, 1);

    await tester.pumpWidget(buildOutput(pagingIdentity: 'exec-1:stdout'));
    await tester.pump();
    await tester.pump();

    expect(find.text('page-1'), findsOneWidget);
    expect(sliceCalls, 1);
  });
}

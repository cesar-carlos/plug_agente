import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_progress_ring.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_data_grid.dart';

class PaintProbe extends SingleChildRenderObjectWidget {
  const PaintProbe({required this.onPaint, required super.child, super.key});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) => ProbeRender(onPaint);
}

class ProbeRender extends RenderProxyBox {
  ProbeRender(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

void main() {
  testWidgets('isolates progress animation from static grid cells', (tester) async {
    var sameRow = 0;
    var otherRow = 0;
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 1200,
          height: 500,
          child: AppDataGridScrollable<int>(
            columns: const [
              AppGridColumn(label: 'Name'),
              AppGridColumn(label: 'Action'),
            ],
            rows: const [0, 1],
            rowHeight: 56,
            rowCells: (row) => [
              PaintProbe(
                onPaint: () {
                  if (row == 0) {
                    sameRow++;
                  } else {
                    otherRow++;
                  }
                },
                child: Text('Static row $row'),
              ),
              if (row == 0)
                const IconButton(
                  onPressed: null,
                  icon: SizedBox.square(dimension: 16, child: AgentActionProgressRing()),
                )
              else
                const Text('Idle'),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    sameRow = 0;
    otherRow = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Diagnostic measurement only; not an estimate of CPU percentage.

    expect(otherRow, 0);
    expect(sameRow, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

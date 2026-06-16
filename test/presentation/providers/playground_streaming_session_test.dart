import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/presentation/providers/playground_streaming_session.dart';

class MockExecuteStreamingQuery extends Mock implements ExecuteStreamingQuery {}

void main() {
  group('PlaygroundStreamingSession', () {
    test('keeps grid rows within UI window while tracking total fetched rows', () async {
      dotenv.loadFromString(
        envString: 'PLAYGROUND_STREAMING_UI_WINDOW_ROWS=3\nPLAYGROUND_STREAMING_MAX_RESULT_ROWS=10',
      );

      final session = PlaygroundStreamingSession(
        executeStreamingQuery: MockExecuteStreamingQuery(),
      );
      final results = <Map<String, dynamic>>[];
      var totalProcessed = 0;

      await session.processChunk(
        chunk: const [
          {'id': 1},
          {'id': 2},
        ],
        results: results,
        onProgress: (rowsProcessed, _) => totalProcessed = rowsProcessed,
        notifyProgress: () {},
        onRowCapReached: (_) {},
      );
      await session.processChunk(
        chunk: const [
          {'id': 3},
          {'id': 4},
        ],
        results: results,
        onProgress: (rowsProcessed, _) => totalProcessed = rowsProcessed,
        notifyProgress: () {},
        onRowCapReached: (_) {},
      );

      expect(totalProcessed, 4);
      expect(results.length, 3);
      expect(results.first['id'], 2);
      expect(results.last['id'], 4);
    });
  });
}

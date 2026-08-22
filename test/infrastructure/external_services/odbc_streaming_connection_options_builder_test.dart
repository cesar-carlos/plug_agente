import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_connection_options_builder.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

void main() {
  test('streaming options set block fetch and caller chunk size without a profile', () {
    final builder = OdbcStreamingConnectionOptionsBuilder(
      settings: MockOdbcConnectionSettings(),
    );

    final options = builder.build(256 * 1024);

    expect(options.blockFetchBatchSize, ConnectionConstants.defaultBlockFetchBatchSize);
    expect(options.streamChunkSizeBytes, 256 * 1024);
  });
}

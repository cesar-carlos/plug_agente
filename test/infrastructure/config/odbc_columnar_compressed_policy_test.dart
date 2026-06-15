import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/infrastructure/config/database_type.dart' as app_db;
import 'package:plug_agente/infrastructure/config/odbc_columnar_compressed_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_policy.dart';

void main() {
  setUp(() {
    dotenv.clean();
  });

  test('preferColumnarCompressedForHighThroughput reads env aliases', () {
    dotenv.loadFromString(envString: 'ODBC_HIGH_THROUGHPUT_COMPRESSED=true');
    expect(preferColumnarCompressedForHighThroughput(), isTrue);

    dotenv.loadFromString(envString: 'ODBC_PREFER_COLUMNAR_COMPRESSED=1');
    expect(preferColumnarCompressedForHighThroughput(), isTrue);
  });

  test('resolveUsageProfileResultEncoding upgrades highThroughput when enabled', () {
    dotenv.loadFromString(envString: 'ODBC_HIGH_THROUGHPUT_COMPRESSED=true');
    expect(
      resolveUsageProfileResultEncoding(OdbcUsageProfile.highThroughput),
      ResultEncoding.columnarCompressed,
    );
    expect(
      resolveEffectiveOdbcResultEncoding(
        databaseType: app_db.DatabaseType.sqlServer,
        usageProfile: OdbcUsageProfile.highThroughput,
      ),
      ResultEncoding.columnarCompressed,
    );
  });
}

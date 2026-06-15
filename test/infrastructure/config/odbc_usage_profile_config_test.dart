import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/infrastructure/config/database_type.dart' as app_db;
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';

void main() {
  setUp(() {
    dotenv.clean();
  });

  group('resolveOdbcUsageProfile', () {
    test('defaults to balancedServer when unset', () {
      expect(resolveOdbcUsageProfile(), OdbcUsageProfile.balancedServer);
      expect(resolveOdbcUsageProfile(rawValue: ''), OdbcUsageProfile.balancedServer);
    });

    test('parses highThroughput aliases', () {
      expect(resolveOdbcUsageProfile(rawValue: 'highThroughput'), OdbcUsageProfile.highThroughput);
      expect(resolveOdbcUsageProfile(rawValue: 'high-throughput'), OdbcUsageProfile.highThroughput);
    });
  });

  group('resolveEffectiveOdbcResultEncoding', () {
    test('uses explicit env override when configured', () {
      expect(
        resolveEffectiveOdbcResultEncoding(
          rawValue: 'rowMajor',
          databaseType: app_db.DatabaseType.sqlServer,
          usageProfile: OdbcUsageProfile.highThroughput,
        ),
        ResultEncoding.rowMajor,
      );
    });

    test('keeps SQL Anywhere on row-major when env is unset', () {
      expect(
        resolveEffectiveOdbcResultEncoding(
          databaseType: app_db.DatabaseType.sybaseAnywhere,
          usageProfile: OdbcUsageProfile.highThroughput,
        ),
        ResultEncoding.rowMajor,
      );
    });

    test('uses profile columnar default for SQL Server on highThroughput when env is unset', () {
      expect(
        resolveEffectiveOdbcResultEncoding(
          databaseType: app_db.DatabaseType.sqlServer,
          usageProfile: OdbcUsageProfile.highThroughput,
        ),
        ResultEncoding.columnar,
      );
    });

    test('upgrades highThroughput when ODBC_HIGH_THROUGHPUT_COMPRESSED is set', () {
      dotenv.loadFromString(envString: 'ODBC_HIGH_THROUGHPUT_COMPRESSED=true');
      expect(
        resolveEffectiveOdbcResultEncoding(
          databaseType: app_db.DatabaseType.sqlServer,
          usageProfile: OdbcUsageProfile.highThroughput,
        ),
        ResultEncoding.columnarCompressed,
      );
    });

    test('keeps row-major for SQL Server on balancedServer when env is unset', () {
      expect(
        resolveEffectiveOdbcResultEncoding(
          databaseType: app_db.DatabaseType.sqlServer,
          usageProfile: OdbcUsageProfile.balancedServer,
        ),
        ResultEncoding.rowMajor,
      );
    });

    test('uses columnar for balancedServer when ODBC_BALANCED_COLUMNAR is set', () {
      dotenv.loadFromString(envString: 'ODBC_BALANCED_COLUMNAR=true');
      expect(
        resolveEffectiveOdbcResultEncoding(
          databaseType: app_db.DatabaseType.sqlServer,
          usageProfile: OdbcUsageProfile.balancedServer,
        ),
        ResultEncoding.columnar,
      );
    });
  });
}

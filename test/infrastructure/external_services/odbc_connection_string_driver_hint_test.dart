import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';

void main() {
  group('connectionStringBenefitsFromLazyStrings', () {
    test('returns true for SQL Server, PostgreSQL, and SQL Anywhere strings', () {
      expect(
        connectionStringBenefitsFromLazyStrings('Driver={ODBC Driver 17 for SQL Server};Server=localhost;'),
        isTrue,
      );
      expect(
        connectionStringBenefitsFromLazyStrings('Driver={PostgreSQL Unicode};Server=localhost;'),
        isTrue,
      );
      expect(
        connectionStringBenefitsFromLazyStrings('Driver={SQL Anywhere 17};dbf=C:/data.db;'),
        isTrue,
      );
    });

    test('returns false for unknown drivers', () {
      expect(connectionStringBenefitsFromLazyStrings('Driver={SQLite3 ODBC Driver};Database=app.db;'), isFalse);
    });
  });

  group('connectionStringPrefersRowMajorStreaming', () {
    test('returns true for SQL Anywhere connection strings', () {
      expect(
        connectionStringPrefersRowMajorStreaming('Driver={SQL Anywhere 17};dbf=C:/data.db;'),
        isTrue,
      );
    });

    test('returns false for SQL Server connection strings', () {
      expect(
        connectionStringPrefersRowMajorStreaming('Driver={ODBC Driver 17 for SQL Server};Server=localhost;'),
        isFalse,
      );
    });
  });

  group('OdbcRecommendedOptionsMerger.lazyStringsForConnectionString', () {
    test('delegates to connection string hints', () {
      expect(
        OdbcRecommendedOptionsMerger.lazyStringsForConnectionString(
          'Driver={ODBC Driver 18 for SQL Server};Server=localhost;',
        ),
        isTrue,
      );
    });
  });
}

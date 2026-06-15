import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/config/odbc_balanced_columnar_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_native_pool_test_on_checkout_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_wire_only_config.dart';

void main() {
  setUp(() {
    dotenv.clean();
  });

  group('odbc_stream_wire_only_config', () {
    test('requires columnar wire before wire-only can activate', () {
      dotenv.loadFromString(envString: 'ODBC_STREAM_WIRE_ONLY=true');
      expect(resolveOdbcStreamWireOnlyEnabled(), isFalse);

      dotenv.loadFromString(
        envString: 'ODBC_STREAM_COLUMNAR_WIRE=true\nODBC_STREAM_WIRE_ONLY=true',
      );
      expect(resolveOdbcStreamWireOnlyEnabled(), isTrue);
    });

    test('honors negotiated columnarWireOnly when env is unset', () {
      dotenv.loadFromString(envString: 'ODBC_STREAM_COLUMNAR_WIRE=true');
      expect(
        resolveOdbcStreamWireOnlyEnabled(
          negotiatedExtensions: const {'columnarWireOnly': true},
        ),
        isTrue,
      );
    });
  });

  group('odbc_balanced_columnar_config', () {
    test('parses ODBC_BALANCED_COLUMNAR aliases', () {
      dotenv.loadFromString(envString: 'ODBC_BALANCED_COLUMNAR=1');
      expect(isOdbcBalancedColumnarEnabled(), isTrue);
    });
  });

  group('odbc_native_pool_test_on_checkout_config', () {
    test('returns null when unset and parses overrides', () {
      expect(readOdbcNativePoolTestOnCheckoutOverride(), isNull);

      dotenv.loadFromString(envString: 'ODBC_NATIVE_POOL_TEST_ON_CHECKOUT=false');
      expect(readOdbcNativePoolTestOnCheckoutOverride(), isFalse);
    });
  });
}

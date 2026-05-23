import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_parser.dart';

export 'package:plug_agente/infrastructure/config/odbc_result_encoding_parser.dart';

ResultEncoding resolveOdbcResultEncoding({String? rawValue}) {
  return resolveOdbcResultEncodingValue(
    rawValue ?? AppEnvironment.get(odbcResultEncodingEnvKey),
  );
}

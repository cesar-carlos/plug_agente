import 'package:plug_agente/core/config/app_environment.dart';

const String odbcStreamColumnarWireEnvKey = 'ODBC_STREAM_COLUMNAR_WIRE';

bool isOdbcStreamColumnarWireEnabled({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcStreamColumnarWireEnvKey))?.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

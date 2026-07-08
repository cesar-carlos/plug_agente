import 'package:plug_agente/core/config/app_environment.dart';

const String odbcBalancedColumnarEnvKey = 'ODBC_BALANCED_COLUMNAR';

bool isOdbcBalancedColumnarEnabled({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcBalancedColumnarEnvKey))?.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

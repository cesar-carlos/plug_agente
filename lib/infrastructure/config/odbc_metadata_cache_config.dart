import 'package:plug_agente/core/config/app_environment.dart';

const String odbcMetadataCacheEnableEnvKey = 'ODBC_METADATA_CACHE_ENABLE';

const int odbcMetadataCacheDefaultMaxEntries = 512;
const int odbcMetadataCacheDefaultTtlSeconds = 300;

bool isOdbcMetadataCacheEnabled({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcMetadataCacheEnableEnvKey))
      ?.trim()
      .toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

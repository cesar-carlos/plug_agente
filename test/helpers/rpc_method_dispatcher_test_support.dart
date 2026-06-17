import 'package:plug_agente/application/rpc/sql_streaming_connection_string_cache.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';

IConfigConnectionStringSource rpcTestConnectionStringSource() => ConfigService(ConfigValidator());

SqlStreamingConnectionStringCache rpcTestStreamingConnectionStringCache() => SqlStreamingConnectionStringCache(
  connectionStringSource: rpcTestConnectionStringSource(),
);

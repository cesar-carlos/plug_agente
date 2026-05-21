import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:result_dart/result_dart.dart';

class LoadAgentConfig {
  LoadAgentConfig(this._activeConfigResolver);
  final ActiveConfigResolver _activeConfigResolver;

  Future<Result<Config>> call(String? id) async {
    if (id != null && id.isNotEmpty) {
      return _activeConfigResolver.resolveExplicit(id);
    }
    return _activeConfigResolver.resolveActiveOrFallback();
  }
}

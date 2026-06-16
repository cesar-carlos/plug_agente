import 'package:plug_agente/domain/repositories/i_odbc_runtime_reloader.dart';

class ReloadOdbcRuntimeDependencies {
  ReloadOdbcRuntimeDependencies(this._reloader);

  final IOdbcRuntimeReloader _reloader;

  Future<bool> call() => _reloader.reload();
}

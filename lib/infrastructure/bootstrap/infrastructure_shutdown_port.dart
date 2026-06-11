import 'package:get_it/get_it.dart';
import 'package:plug_agente/core/services/i_app_infrastructure_shutdown_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

final class InfrastructureShutdownPort implements IAppInfrastructureShutdownPort {
  const InfrastructureShutdownPort(this._getIt);

  final GetIt _getIt;

  @override
  Future<void> closeLocalDatabase() async {
    if (!_getIt.isRegistered<AppDatabase>()) {
      return;
    }
    await _getIt<AppDatabase>().close();
  }

  @override
  void disposeMetricsCollectors() {
    if (_getIt.isRegistered<MetricsCollector>()) {
      _getIt<MetricsCollector>().dispose();
    }
    if (_getIt.isRegistered<ProtocolMetricsCollector>()) {
      _getIt<ProtocolMetricsCollector>().dispose();
    }
    if (_getIt.isRegistered<ISqlInvestigationCollector>()) {
      _getIt<ISqlInvestigationCollector>().dispose();
    }
  }

  @override
  Future<void> disposeOdbcEventBridge() async {
    if (_getIt.isRegistered<OdbcEventBridge>()) {
      await _getIt<OdbcEventBridge>().dispose();
    }
  }
}

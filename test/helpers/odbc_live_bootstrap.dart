import 'package:odbc_fast/odbc_fast.dart' as odbc;

/// Shared ODBC `ServiceLocator` lifecycle for live tests (streaming, SQL probes).
///
/// RPC live tests use `OdbcE2eRpcHarness`, which owns its own locator and pool.
class OdbcLiveBootstrap {
  OdbcLiveBootstrap._(this._locator);

  final odbc.ServiceLocator _locator;

  odbc.OdbcService get asyncService => _locator.asyncService;

  /// Returns null when native ODBC init fails.
  static Future<OdbcLiveBootstrap?> open() async {
    final locator = odbc.ServiceLocator()..initialize(useAsync: true);
    final service = locator.asyncService;
    final initResult = await service.initialize();
    if (initResult.isError()) {
      locator.shutdown();
      return null;
    }
    return OdbcLiveBootstrap._(locator);
  }

  void shutdown() {
    _locator.shutdown();
  }
}

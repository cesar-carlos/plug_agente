import 'package:odbc_fast/odbc_fast.dart' as odbc;

odbc.ServiceLocator _odbcWorkerLocator = odbc.ServiceLocator();

odbc.ServiceLocator get odbcWorkerLocator => _odbcWorkerLocator;

void setOdbcWorkerLocator(odbc.ServiceLocator locator) {
  _odbcWorkerLocator = locator;
}

void shutdownOdbcWorker() => _odbcWorkerLocator.shutdown();

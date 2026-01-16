abstract class Failure implements Exception {
  final String message;
  Failure(this.message);
  
  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  ServerFailure(super.message);
}

class NetworkFailure extends Failure {
  NetworkFailure(super.message);
}

class DatabaseFailure extends Failure {
  DatabaseFailure(super.message);
}

class ValidationFailure extends Failure {
  ValidationFailure(super.message);
}

class NotFoundFailure extends Failure {
  NotFoundFailure(super.message);
}

class ConfigurationFailure extends Failure {
  ConfigurationFailure(super.message);
}

class ConnectionFailure extends Failure {
  ConnectionFailure(super.message);
}

class QueryExecutionFailure extends Failure {
  QueryExecutionFailure(super.message);
}

class CompressionFailure extends Failure {
  CompressionFailure(super.message);
}

class NotificationFailure extends Failure {
  NotificationFailure(super.message);
}
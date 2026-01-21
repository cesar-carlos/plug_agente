class ConnectionString {
  final String value;

  ConnectionString(this.value) {
    if (!_isValid(value)) {
      throw ArgumentError('Invalid connection string: $value');
    }
  }

  bool _isValid(String connectionString) {
    if (connectionString.isEmpty) return false;

    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionString && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

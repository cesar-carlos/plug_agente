class AgentId {
  final String value;

  AgentId(this.value) {
    if (!_isValid(value)) {
      throw ArgumentError('Invalid agent ID: $value');
    }
  }

  bool _isValid(String agentId) {
    if (agentId.isEmpty) return false;

    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

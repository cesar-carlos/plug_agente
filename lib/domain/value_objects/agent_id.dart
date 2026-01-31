// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: Value object compares by value for equality.

class AgentId {
  AgentId(this.value) {
    if (!_isValid(value)) {
      throw ArgumentError('Invalid agent ID: $value');
    }
  }
  final String value;

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

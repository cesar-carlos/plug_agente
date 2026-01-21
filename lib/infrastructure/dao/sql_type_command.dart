class SqlTypeCommand {
  String name;
  String? _type;
  Object? _value;

  SqlTypeCommand(this.name);

  set asInt(int? value) {
    _value = value;
    _type = 'int';
  }

  int? get asInt {
    if (_value == null) return null;
    return int.parse(_value.toString());
  }

  set asString(String? value) {
    _value = value;
    _type = 'string';
  }

  String? get asString {
    if (_value == null) return null;
    return _value.toString();
  }

  set asDate(DateTime? value) {
    _value = value?.toIso8601String();
    _type = 'date';
  }

  DateTime? get asDate {
    if (_value == null) return null;
    return DateTime.parse(_value.toString());
  }

  set asDouble(double? value) {
    _value = value;
    _type = 'double';
  }

  double? get asDouble {
    if (_value == null) return null;
    return double.parse(_value.toString());
  }

  set asBool(bool? value) {
    _value = value;
    _type = 'bool';
  }

  bool? get asBool {
    if (_value == null) return null;
    return _value.toString().toLowerCase() == 'true';
  }

  bool get isSingleQuote {
    switch (_type) {
      case 'string':
      case 'date':
        return true;
      default:
        return false;
    }
  }

  dynamic get value => _value;

  @override
  String toString() {
    return 'Value: $_value, Type: $_type, Name: $name';
  }
}

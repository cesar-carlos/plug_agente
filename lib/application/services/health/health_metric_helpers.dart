int healthMetricInt(Map<String, Object?> metrics, String key) {
  final value = metrics[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

double healthQuerySuccessRate(int total, int errors) {
  if (total == 0) {
    return 100;
  }
  final successful = total - errors;
  return (successful / total * 100).clamp(0, 100);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/shared/widgets/sql/query_result_column_type.dart';

void main() {
  const type = QueryResultColumnType();

  test('orders native SQL types without converting their values to text', () {
    expect(type.compare(2, 11), isNegative);
    expect(type.compare(2.1, 2), isPositive);
    expect(type.compare(DateTime(2026), DateTime(2025)), isPositive);
    expect(type.compare(false, true), isNegative);
    expect(type.compare(null, 0), isNegative);
    expect(type.compare(0, null), isPositive);
    expect(type.compare(null, null), 0);
    expect(type.compare('0012', '0020'), isNegative);
    expect(type.makeCompareValue(null), isNull);
    expect(type.makeCompareValue(12.3456789), 12.3456789);
  });
}

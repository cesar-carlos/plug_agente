import 'package:pluto_grid/pluto_grid.dart';

/// Keeps SQL values intact instead of coercing numbers, dates and nulls to text.
class QueryResultColumnType extends PlutoColumnTypeText {
  const QueryResultColumnType();

  @override
  bool isValid(dynamic value) => true;

  @override
  dynamic makeCompareValue(dynamic v) => v;

  @override
  int compare(dynamic a, dynamic b) {
    if (identical(a, b)) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
    return a.toString().compareTo(b.toString());
  }
}

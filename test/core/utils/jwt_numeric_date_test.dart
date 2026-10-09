import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/jwt_numeric_date.dart';

void main() {
  test('absent dates remain optional', () {
    expect(parseJwtNumericDate(null, claim: 'exp'), isNull);
  });

  test('fractional dates retain microsecond precision in UTC', () {
    final parsed = parseJwtNumericDate(0.25, claim: 'exp')!;
    expect(parsed.microsecondsSinceEpoch, 250000);
    expect(parsed.isUtc, isTrue);
    expect(parseJwtNumericDate(-0.25, claim: 'nbf')!.microsecondsSinceEpoch, -250000);
  });

  test('sub-microsecond dates conservatively round down', () {
    expect(parseJwtNumericDate(0.0000009, claim: 'exp')!.microsecondsSinceEpoch, 0);
    expect(parseJwtNumericDate(-0.0000001, claim: 'exp')!.microsecondsSinceEpoch, -1);
  });

  test('supported DateTime boundaries are accepted', () {
    for (final seconds in [-8640000000000, 8640000000000]) {
      expect(parseJwtNumericDate(seconds, claim: 'exp')!.millisecondsSinceEpoch, seconds * 1000);
    }
  });

  test('invalid types and non-finite dates fail without exposing input', () {
    for (final value in <Object>['sensitive-value', true, <String, Object>{}, double.nan, double.infinity]) {
      expect(
        () => parseJwtNumericDate(value, claim: 'exp'),
        throwsA(
          isA<FormatException>().having((error) => error.toString(), 'diagnostic', isNot(contains('sensitive-value'))),
        ),
      );
    }
  });

  test('out-of-range dates fail before DateTime construction', () {
    for (final seconds in [-8640000000001, 8640000000001, 1e100, -1e100]) {
      expect(() => parseJwtNumericDate(seconds, claim: 'exp'), throwsFormatException);
    }
  });
}

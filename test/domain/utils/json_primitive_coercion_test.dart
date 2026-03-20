import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';

void main() {
  group('jsonWholeNumberAsInt', () {
    test('should accept int and double whole numbers', () {
      expect(jsonWholeNumberAsInt(42), 42);
      expect(jsonWholeNumberAsInt(42.0), 42);
    });

    test('should reject fractional doubles', () {
      expect(jsonWholeNumberAsInt(1.5), isNull);
    });

    test('should reject non-numeric', () {
      expect(jsonWholeNumberAsInt('1'), isNull);
      expect(jsonWholeNumberAsInt(null), isNull);
    });
  });

  group('jsonPositiveInt', () {
    test('should require value >= 1', () {
      expect(jsonPositiveInt(1), 1);
      expect(jsonPositiveInt(1.0), 1);
      expect(jsonPositiveInt(0), isNull);
      expect(jsonPositiveInt(-1), isNull);
    });
  });

  group('jsonNonNegativeInt', () {
    test('should require value >= 0', () {
      expect(jsonNonNegativeInt(0), 0);
      expect(jsonNonNegativeInt(3), 3);
      expect(jsonNonNegativeInt(-1), isNull);
    });
  });

  group('defaults', () {
    test('jsonPositiveIntWithDefault falls back', () {
      expect(jsonPositiveIntWithDefault(null, 99), 99);
      expect(jsonPositiveIntWithDefault(5, 99), 5);
    });

    test('jsonNonNegativeIntWithDefault falls back', () {
      expect(jsonNonNegativeIntWithDefault(null, 30), 30);
      expect(jsonNonNegativeIntWithDefault(-1, 30), 30);
    });
  });
}

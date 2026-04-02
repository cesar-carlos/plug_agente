import 'package:plug_agente/application/validation/zard_adapter.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:zard/zard.dart';

class InputValidators {
  InputValidators._();

  static final RegExp _usernameCharClass = RegExp(r'^[a-z0-9_-]+$');
  static final RegExp _databaseNameCharClass = RegExp(r'^[a-zA-Z0-9_]+$');
  static final RegExp _digitsOnlyRegex = RegExp(r'^\d+$');

  static Result<String> email(
    String value, {
    String? message,
  }) {
    final schema = z.string().email(message: message ?? 'Invalid email address').trim().toLowerCase();

    return schema.parseSafe(value);
  }

  static Result<String> emailStrict(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .email(
          pattern: z.regexes.email,
          message: message ?? 'Invalid email address',
        )
        .trim()
        .toLowerCase();

    return schema.parseSafe(value);
  }

  static Result<String> url(
    String value, {
    String? message,
  }) {
    final schema = z.string().url(message: message ?? 'Invalid URL').trim();

    return schema.parseSafe(value);
  }

  static Result<String> httpUrl(
    String value, {
    String? message,
  }) {
    final schema = z.string().httpUrl(message: message ?? 'Invalid HTTP(S) URL').trim();

    return schema.parseSafe(value);
  }

  static Result<String> hostname(
    String value, {
    String? message,
  }) {
    final schema = z.string().hostname(message: message ?? 'Invalid hostname').trim().toLowerCase();

    return schema.parseSafe(value);
  }

  static Result<String> ipv4(
    String value, {
    String? message,
  }) {
    final schema = z.string().ipv4(message: message ?? 'Invalid IPv4 address').trim();

    return schema.parseSafe(value);
  }

  static Result<int> port(
    int value, {
    String? message,
  }) {
    final schema = z.int()
        .min(1, message: message ?? 'Port must be at least 1')
        .max(65535, message: message ?? 'Port must be at most 65535');

    return schema.parseSafe(value);
  }

  static Result<String> nonEmptyString(
    String value, {
    int? minLength,
    int? maxLength,
    String? message,
  }) {
    var schema = z.string().trim();

    if (minLength != null) {
      schema = schema.min(
        minLength,
        message: message ?? 'Value must be at least $minLength characters',
      );
    }

    if (maxLength != null) {
      schema = schema.max(
        maxLength,
        message: message ?? 'Value must be at most $maxLength characters',
      );
    }

    return schema.parseSafe(value);
  }

  static Result<String> username(
    String value, {
    int minLength = 3,
    int maxLength = 50,
    String? message,
  }) {
    final schema = z
        .string()
        .min(
          minLength,
          message: message ?? 'Username must be at least $minLength characters',
        )
        .max(
          maxLength,
          message: message ?? 'Username must be at most $maxLength characters',
        )
        .trim()
        .toLowerCase()
        .refine(
          _usernameCharClass.hasMatch,
          message: message ?? 'Username can only contain letters, numbers, underscores, and hyphens',
        );

    return schema.parseSafe(value);
  }

  static Result<String> databaseName(
    String value, {
    int minLength = 1,
    int maxLength = 64,
    String? message,
  }) {
    final schema = z
        .string()
        .min(
          minLength,
          message: message ?? 'Database name must be at least $minLength character(s)',
        )
        .max(
          maxLength,
          message: message ?? 'Database name must be at most $maxLength characters',
        )
        .trim()
        .refine(
          _databaseNameCharClass.hasMatch,
          message: message ?? 'Database name can only contain letters, numbers, and underscores',
        );

    return schema.parseSafe(value);
  }

  static Result<String> cep(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .trim()
        .refine(
          (String raw) {
            final digits = _digitsOnly(raw);
            return digits.length == 8 && _digitsOnlyRegex.hasMatch(digits);
          },
          message: message ?? 'Invalid CEP',
        )
        .transformTyped(_digitsOnly);

    return schema.parseSafe(value);
  }

  static Result<String> phone(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .trim()
        .refine(
          (String raw) {
            final digits = _digitsOnly(raw);
            return digits.length == 10 && _digitsOnlyRegex.hasMatch(digits);
          },
          message: message ?? 'Invalid phone number',
        )
        .transformTyped(_digitsOnly);

    return schema.parseSafe(value);
  }

  static Result<String> mobile(
    String value, {
    String? message,
  }) {
    final schema = z
        .string()
        .trim()
        .refine((String raw) {
          final digits = _digitsOnly(raw);
          final hasValidLength = digits.length == 11 && _digitsOnlyRegex.hasMatch(digits);
          final startsWithNine = digits.length == 11 && digits.length > 2 && digits[2] == '9';
          return hasValidLength && startsWithNine;
        }, message: message ?? 'Invalid mobile number')
        .transformTyped(_digitsOnly);

    return schema.parseSafe(value);
  }

  static Result<String> cpfOrCnpj(
    String value, {
    String? message,
  }) {
    final digits = _digitsOnly(value);
    if (digits.length == 11 && _isValidCpf(digits)) {
      return Success(digits);
    }
    if (digits.length == 14 && _isValidCnpj(digits)) {
      return Success(digits);
    }
    return Failure(
      domain.ValidationFailure(message ?? 'Invalid CPF/CNPJ'),
    );
  }

  static String documentType(String value) {
    final digits = _digitsOnly(value);
    if (digits.length == 14) {
      return 'cnpj';
    }
    return 'cpf';
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(RegExp('[^0-9]'), '');
  }

  static bool _isAllDigitsEqual(String digits) {
    if (digits.isEmpty) {
      return true;
    }
    return digits.split('').every((digit) => digit == digits[0]);
  }

  static bool _isValidCpf(String cpf) {
    if (cpf.length != 11 || _isAllDigitsEqual(cpf)) {
      return false;
    }

    final numbers = cpf.split('').map(int.parse).toList(growable: false);
    final firstCheck = _cpfCheckDigit(numbers, 9);
    final secondCheck = _cpfCheckDigit(numbers, 10);
    return numbers[9] == firstCheck && numbers[10] == secondCheck;
  }

  static int _cpfCheckDigit(List<int> digits, int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += digits[i] * ((length + 1) - i);
    }
    final mod = (sum * 10) % 11;
    return mod == 10 ? 0 : mod;
  }

  static bool _isValidCnpj(String cnpj) {
    if (cnpj.length != 14 || _isAllDigitsEqual(cnpj)) {
      return false;
    }

    final numbers = cnpj.split('').map(int.parse).toList(growable: false);
    final firstCheck = _cnpjCheckDigit(
      numbers,
      const [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    );
    final secondCheck = _cnpjCheckDigit(
      numbers,
      const [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    );
    return numbers[12] == firstCheck && numbers[13] == secondCheck;
  }

  static int _cnpjCheckDigit(List<int> digits, List<int> weights) {
    var sum = 0;
    for (var i = 0; i < weights.length; i++) {
      sum += digits[i] * weights[i];
    }
    final mod = sum % 11;
    return mod < 2 ? 0 : 11 - mod;
  }
}

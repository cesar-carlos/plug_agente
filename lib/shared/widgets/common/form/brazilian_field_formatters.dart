import 'package:brasil_fields/brasil_fields.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class BrazilianFieldFormatters {
  static final List<TextInputFormatter> document = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(14),
    CpfOuCnpjFormatter(),
  ];

  static final List<TextInputFormatter> phone = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(11),
    TelefoneInputFormatter(),
  ];

  static final List<TextInputFormatter> postalCode = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(8),
    CepInputFormatter(),
  ];

  static final List<TextInputFormatter> state = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
    LengthLimitingTextInputFormatter(2),
    const UpperCaseTextFormatter(),
  ];

  static void apply(
    TextEditingController controller,
    String rawValue,
    List<TextInputFormatter> formatters,
  ) {
    final formatted = format(rawValue, formatters);
    if (controller.text == formatted) {
      return;
    }

    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Applies [formatters] in sequence starting from an empty "old" value.
  ///
  /// Package `brasil_fields` formatters assume live editing; chaining them
  /// with a blank [TextEditingValue] matches how digits are typed incrementally.
  static String format(
    String rawValue,
    List<TextInputFormatter> formatters,
  ) {
    var value = TextEditingValue(
      text: rawValue,
      selection: TextSelection.collapsed(offset: rawValue.length),
    );

    for (final formatter in formatters) {
      value = formatter.formatEditUpdate(const TextEditingValue(), value);
    }

    return value.text;
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upperText = newValue.text.toUpperCase();
    return TextEditingValue(
      text: upperText,
      selection: TextSelection.collapsed(offset: upperText.length),
    );
  }
}

// lib/shared/utils/input_formatters.dart

import 'package:flutter/services.dart';

/// Formats card numbers as groups of 4 digits separated by spaces.
/// e.g. "1234567890123456" → "1234 5678 9012 3456"
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final text = newValue.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buf.write(text[i]);
      if ((i + 1) % 4 == 0 && i != text.length - 1) buf.write(' ');
    }
    return TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
  }
}

/// Automatically inserts a "/" after the first two digits.
/// e.g. "1227" → "12/27"
class ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final text = newValue.text.replaceAll('/', '');
    if (text.length >= 2) {
      final formatted = '${text.substring(0, 2)}/${text.substring(2)}';
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return newValue;
  }
}
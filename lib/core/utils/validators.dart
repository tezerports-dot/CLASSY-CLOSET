class Validators {
  Validators._();

  static String? requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  static String? nonNegativeNumber(String? value) {
    final parsed = num.tryParse(value ?? '');
    if (parsed == null) return 'Enter a number';
    if (parsed < 0) return 'Must be zero or greater';
    return null;
  }
}

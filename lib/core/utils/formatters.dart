import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  /// Set once from the saved store profile so every screen and every printed
  /// document shows the same currency.
  static String _symbol = '₹';
  static String _locale = 'en_IN';

  static String get symbol => _symbol;

  /// Indian grouping puts the first separator after three digits and every two
  /// after that — 12,34,567 rather than 1,234,567 — so the locale matters as
  /// much as the symbol.
  static void configure({String? symbol, String? locale}) {
    if (symbol != null && symbol.trim().isNotEmpty) _symbol = symbol.trim();
    if (locale != null && locale.trim().isNotEmpty) _locale = locale.trim();
    _currencyCache = null;
    _plainCache = null;
  }

  static NumberFormat? _currencyCache;
  static NumberFormat? _plainCache;

  static NumberFormat get _currency => _currencyCache ??= NumberFormat.currency(
    locale: _locale,
    symbol: _symbol,
    decimalDigits: 2,
  );

  static NumberFormat get _plain => _plainCache ??=
      NumberFormat.decimalPatternDigits(locale: _locale, decimalDigits: 2);

  static final _dateTime = DateFormat('dd MMM y, h:mm a');
  static final _date = DateFormat('dd MMM y');

  static String currency(num value) => _currency.format(value);

  /// Amount without the symbol, for invoice columns that carry it in the header.
  static String amount(num value) => _plain.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);
  static String date(DateTime value) => _date.format(value);

  static String quantity(num value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  static final _currency = NumberFormat.simpleCurrency(name: 'USD');
  static final _dateTime = DateFormat('MMM d, y h:mm a');

  static String currency(num value) => _currency.format(value);
  static String dateTime(DateTime value) => _dateTime.format(value);
}

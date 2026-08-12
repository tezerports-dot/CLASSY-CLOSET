/// Report shapes, built from sale lines rather than from bill headers so tax
/// and margin can be broken down the way a GST return and a buyer both need.
library;

/// A window of time a report covers.
class DateRange {
  const DateRange(this.from, this.to, this.label);

  /// Inclusive start.
  final DateTime from;

  /// Exclusive end, so a day range is [midnight, next midnight).
  final DateTime to;
  final String label;

  bool contains(DateTime moment) =>
      !moment.isBefore(from) && moment.isBefore(to);

  static DateRange today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return DateRange(start, start.add(const Duration(days: 1)), 'Today');
  }

  static DateRange thisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    return DateRange(
      start,
      today.add(const Duration(days: 1)),
      'This week',
    );
  }

  static DateRange thisMonth() {
    final now = DateTime.now();
    return DateRange(
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1),
      'This month',
    );
  }

  static DateRange lastMonth() {
    final now = DateTime.now();
    return DateRange(
      DateTime(now.year, now.month - 1),
      DateTime(now.year, now.month),
      'Last month',
    );
  }

  /// April to March, which is how Indian returns are filed.
  static DateRange thisFinancialYear() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return DateRange(
      DateTime(startYear, 4),
      DateTime(startYear + 1, 4),
      'This financial year',
    );
  }

  static DateRange custom(DateTime from, DateTime to) => DateRange(
    DateTime(from.year, from.month, from.day),
    DateTime(to.year, to.month, to.day).add(const Duration(days: 1)),
    'Custom',
  );
}

/// One bill in the sales register.
class RegisterRow {
  const RegisterRow({
    required this.receiptNumber,
    required this.soldAt,
    required this.customerName,
    required this.customerGstin,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.discount,
    required this.grandTotal,
    required this.profit,
    required this.paymentMethod,
    required this.cashAmount,
    required this.cardAmount,
    required this.upiAmount,
    required this.soldBy,
  });

  final String receiptNumber;
  final DateTime soldAt;
  final String customerName;
  final String? customerGstin;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final double discount;
  final double grandTotal;
  final double profit;
  final String paymentMethod;
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final String soldBy;

  double get taxTotal => cgst + sgst + igst;
}

/// Tax grouped by rate, which is the shape a GSTR-1 summary wants.
class GstRateSummary {
  const GstRateSummary({
    required this.ratePercent,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.lineCount,
  });

  final double ratePercent;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final int lineCount;

  double get taxTotal => cgst + sgst + igst;
  double get total => taxableValue + taxTotal;
}

/// Tax grouped by HSN code, required on the return above a turnover threshold.
class HsnSummary {
  const HsnSummary({
    required this.hsnCode,
    required this.description,
    required this.quantity,
    required this.taxableValue,
    required this.taxAmount,
    required this.total,
  });

  final String hsnCode;
  final String description;
  final double quantity;
  final double taxableValue;
  final double taxAmount;
  final double total;
}

/// How a product performed over the window.
class ProductPerformance {
  const ProductPerformance({
    required this.productId,
    required this.description,
    required this.quantitySold,
    required this.revenue,
    required this.profit,
    required this.stockOnHand,
  });

  final int productId;
  final String description;
  final double quantitySold;
  final double revenue;
  final double profit;
  final double stockOnHand;

  double get marginPercent => revenue == 0 ? 0 : profit / revenue * 100;
}

/// The whole picture for one window.
class ReportBundle {
  const ReportBundle({
    required this.range,
    required this.register,
    required this.gstByRate,
    required this.hsn,
    required this.topSellers,
    required this.deadStock,
    required this.returnsTotal,
    required this.returnsTax,
    required this.returnCount,
  });

  final DateRange range;
  final List<RegisterRow> register;
  final List<GstRateSummary> gstByRate;
  final List<HsnSummary> hsn;
  final List<ProductPerformance> topSellers;

  /// In stock but nothing sold in the window — the money sitting on the rail.
  final List<ProductPerformance> deadStock;
  final double returnsTotal;
  final double returnsTax;
  final int returnCount;

  int get billCount => register.length;
  double get grossSales =>
      register.fold(0.0, (sum, r) => sum + r.grandTotal);
  double get taxableTotal =>
      register.fold(0.0, (sum, r) => sum + r.taxableValue);
  double get taxTotal => register.fold(0.0, (sum, r) => sum + r.taxTotal);
  double get discountTotal =>
      register.fold(0.0, (sum, r) => sum + r.discount);
  double get grossProfit => register.fold(0.0, (sum, r) => sum + r.profit);
  double get cashTotal => register.fold(0.0, (sum, r) => sum + r.cashAmount);
  double get cardTotal => register.fold(0.0, (sum, r) => sum + r.cardAmount);
  double get upiTotal => register.fold(0.0, (sum, r) => sum + r.upiAmount);

  /// Sales less what came back — the figure that actually belongs to the shop.
  double get netSales => grossSales - returnsTotal;
  double get netTax => taxTotal - returnsTax;
  double get averageBill => billCount == 0 ? 0 : grossSales / billCount;
  double get marginPercent =>
      grossSales == 0 ? 0 : grossProfit / grossSales * 100;
}

/// Turns rows into CSV that Excel and Tally will both open.
///
/// Quotes every field and doubles any embedded quote, so a product name with a
/// comma in it cannot shift the columns.
String toCsv(List<String> headers, List<List<Object?>> rows) {
  final buffer = StringBuffer()..writeln(headers.map(_csvCell).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(_csvCell).join(','));
  }
  return buffer.toString();
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  return '"${text.replaceAll('"', '""')}"';
}

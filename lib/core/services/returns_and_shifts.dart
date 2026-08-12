/// Value types for taking goods back and for running a till session.
///
/// These are plain data so the POS, the returns screen and the reports can all
/// speak the same language without reaching into Drift rows.
library;

/// One line of a bill being looked up for a return.
class ReturnableLine {
  ReturnableLine({
    required this.saleItemId,
    required this.productId,
    required this.description,
    required this.hsnCode,
    required this.soldQuantity,
    required this.alreadyReturned,
    required this.unitPrice,
    required this.lineTotal,
    required this.taxRate,
    required this.taxableValue,
    required this.taxAmount,
    required this.costPrice,
  });

  final int saleItemId;
  final int productId;
  final String description;
  final String hsnCode;
  final double soldQuantity;

  /// How many of these have come back on earlier returns, so the same shirt
  /// cannot be refunded twice.
  final double alreadyReturned;
  final double unitPrice;
  final double lineTotal;
  final double taxRate;
  final double taxableValue;
  final double taxAmount;
  final double costPrice;

  double get returnableQuantity => soldQuantity - alreadyReturned;
  bool get isFullyReturned => returnableQuantity <= 0;

  /// Refund for [quantity] of this line, keeping the original per-unit price
  /// including its share of any discount that was given.
  double refundFor(double quantity) =>
      soldQuantity == 0 ? 0 : lineTotal / soldQuantity * quantity;
}

/// A bill found by its number, with everything a return needs.
class ReturnableSale {
  ReturnableSale({
    required this.saleId,
    required this.receiptNumber,
    required this.soldAt,
    required this.customerId,
    required this.customerName,
    required this.grandTotal,
    required this.isInterState,
    required this.lines,
  });

  final int saleId;
  final String receiptNumber;
  final DateTime soldAt;
  final int? customerId;
  final String customerName;
  final double grandTotal;
  final bool isInterState;
  final List<ReturnableLine> lines;

  bool get hasAnythingLeft => lines.any((l) => !l.isFullyReturned);
}

/// How many of one line the customer is bringing back.
class ReturnSelection {
  const ReturnSelection({required this.line, required this.quantity});
  final ReturnableLine line;
  final double quantity;
}

/// How the money goes back to the customer.
enum RefundMethod {
  cash('Cash from the drawer'),
  card('Back to their card'),
  upi('Back by UPI'),
  credit('Credit on their account');

  const RefundMethod(this.label);
  final String label;

  String get code => name;

  static RefundMethod fromCode(String? code) {
    for (final method in RefundMethod.values) {
      if (method.name == code) return method;
    }
    return RefundMethod.cash;
  }
}

/// A completed return, as it went into the books.
class ReturnRecord {
  ReturnRecord({
    required this.id,
    required this.returnNumber,
    required this.saleReceipt,
    required this.customerName,
    required this.totalAmount,
    required this.taxableTotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.refundMethod,
    required this.returnedAt,
    this.reason,
    this.lineCount = 0,
  });

  final int id;
  final String returnNumber;
  final String saleReceipt;
  final String customerName;
  final double totalAmount;
  final double taxableTotal;
  final double cgst;
  final double sgst;
  final double igst;
  final RefundMethod refundMethod;
  final DateTime returnedAt;
  final String? reason;
  final int lineCount;

  double get taxTotal => cgst + sgst + igst;
}

/// A till session.
class ShiftRecord {
  ShiftRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.openedAt,
    required this.openingFloat,
    this.closedAt,
    this.closingCount,
    this.expectedCash,
    this.cashSales = 0,
    this.cardSales = 0,
    this.upiSales = 0,
    this.cashRefunds = 0,
    this.paidIn = 0,
    this.paidOut = 0,
    this.saleCount = 0,
    this.notes,
  });

  final int id;
  final int userId;
  final String userName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double? closingCount;
  final double? expectedCash;
  final double cashSales;
  final double cardSales;
  final double upiSales;
  final double cashRefunds;
  final double paidIn;
  final double paidOut;
  final int saleCount;
  final String? notes;

  bool get isOpen => closedAt == null;

  /// What should be in the drawer: the float, plus cash taken, less cash
  /// refunded and any money moved out.
  double get computedExpectedCash =>
      openingFloat + cashSales + paidIn - cashRefunds - paidOut;

  /// Counted less expected. Negative is a shortfall.
  double? get variance => closingCount == null
      ? null
      : closingCount! - (expectedCash ?? computedExpectedCash);

  double get totalTakings => cashSales + cardSales + upiSales;
}

/// Money in or out of the drawer that was not a sale.
class CashMovementRecord {
  const CashMovementRecord({
    required this.id,
    required this.isIn,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  final int id;
  final bool isIn;
  final double amount;
  final String reason;
  final DateTime createdAt;
}

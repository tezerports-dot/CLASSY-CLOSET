/// Bills parked mid-sale while the customer tries something on.
library;

/// One line of a parked bill.
class HeldBillLine {
  const HeldBillLine({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
  });

  final int productId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double discount;

  double get total => quantity * unitPrice - discount;
}

/// A whole parked bill, as it will look in the recall list.
class HeldBillRecord {
  const HeldBillRecord({
    required this.id,
    required this.label,
    required this.heldAt,
    required this.lines,
    this.customerName,
  });

  final int id;

  /// What the counter called it — a name, a phone, "blue shirt man".
  final String label;
  final DateTime heldAt;
  final List<HeldBillLine> lines;
  final String? customerName;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);
  double get total => lines.fold(0.0, (sum, l) => sum + l.total);
}

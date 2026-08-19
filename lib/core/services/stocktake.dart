/// Physical stock counts and the adjustments they produce.
library;

/// Where a count session has got to.
enum StocktakeStatus {
  /// Being counted. Lines can still be entered and changed.
  open,

  /// Applied to stock. Frozen from here on.
  committed,

  /// Walked away from without applying anything.
  abandoned;

  String get label => switch (this) {
    StocktakeStatus.open => 'Counting',
    StocktakeStatus.committed => 'Applied',
    StocktakeStatus.abandoned => 'Abandoned',
  };

  static StocktakeStatus fromName(String? name) => StocktakeStatus.values
      .firstWhere((s) => s.name == name, orElse: () => StocktakeStatus.open);
}

/// One counted line.
class StocktakeLine {
  const StocktakeLine({
    required this.productId,
    required this.description,
    required this.sku,
    required this.systemQuantity,
    required this.countedQuantity,
    required this.costPrice,
    required this.countedAt,
  });

  final int productId;
  final String description;
  final String sku;

  /// What the books said when this line was counted.
  final double systemQuantity;
  final double countedQuantity;
  final double costPrice;
  final DateTime countedAt;

  /// Positive means more on the rail than the books say.
  double get variance => countedQuantity - systemQuantity;

  /// What the difference is worth at cost. Negative is money walked out.
  double get varianceValue => variance * costPrice;

  bool get matches => variance.abs() < 0.0001;
}

/// A whole count session.
class StocktakeRecord {
  const StocktakeRecord({
    required this.id,
    required this.reference,
    required this.status,
    required this.startedAt,
    required this.lines,
    this.committedAt,
    this.userName = '',
    this.notes = '',
  });

  final int id;
  final String reference;
  final StocktakeStatus status;
  final DateTime startedAt;
  final DateTime? committedAt;
  final String userName;
  final String notes;
  final List<StocktakeLine> lines;

  bool get isOpen => status == StocktakeStatus.open;
  int get countedLines => lines.length;

  /// Lines where the rail and the books disagree — the only ones worth reading.
  List<StocktakeLine> get discrepancies =>
      lines.where((l) => !l.matches).toList();

  double get shortValue => lines
      .where((l) => l.variance < 0)
      .fold(0.0, (sum, l) => sum + l.varianceValue);

  double get overValue => lines
      .where((l) => l.variance > 0)
      .fold(0.0, (sum, l) => sum + l.varianceValue);

  /// The net effect on the value of stock. Almost always negative: shrinkage.
  double get netValue => shortValue + overValue;
}

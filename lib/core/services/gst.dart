import 'dart:convert';

/// One GST rate band, selected by the selling price of a single piece.
///
/// Indian apparel is taxed on a per-piece slab: under GST 2.0 (in force from
/// 22 September 2025) a garment at or below Rs 2,500 a piece attracts 5% and
/// anything above attracts 18%. The bands are data rather than constants
/// because that threshold has already moved once — it was Rs 1,000 before —
/// and a shop must be able to correct it without a new build.
class GstSlab {
  const GstSlab({required this.upToPrice, required this.ratePercent});

  /// Inclusive upper bound for the price of one piece. `null` is the open-ended
  /// top band.
  final double? upToPrice;
  final double ratePercent;

  Map<String, dynamic> toJson() => {
    'upToPrice': upToPrice,
    'ratePercent': ratePercent,
  };

  factory GstSlab.fromJson(Map<String, dynamic> json) => GstSlab(
    upToPrice: (json['upToPrice'] as num?)?.toDouble(),
    ratePercent: (json['ratePercent'] as num?)?.toDouble() ?? 0,
  );
}

/// The shop's GST configuration: how a rate is chosen and how the total is
/// split between the tax heads.
class GstSettings {
  const GstSettings({
    this.enabled = true,
    this.pricesIncludeTax = true,
    this.slabs = defaultApparelSlabs,
    this.defaultHsnCode = '6109',
  });

  /// Apparel bands as they stand after GST 2.0. Verify against your own CA
  /// before going live — this is a default, not tax advice.
  static const List<GstSlab> defaultApparelSlabs = [
    GstSlab(upToPrice: 2500, ratePercent: 5),
    GstSlab(upToPrice: null, ratePercent: 18),
  ];

  final bool enabled;

  /// Indian retail almost always quotes a shelf price that already contains
  /// GST, so the tax is extracted from the price rather than added on top.
  final bool pricesIncludeTax;
  final List<GstSlab> slabs;
  final String defaultHsnCode;

  /// The rate for one piece at [unitPrice]. An explicit [productRate] set on the
  /// product always wins; the slabs only fill in when the product has no rate
  /// of its own.
  double rateFor({required double unitPrice, double? productRate}) {
    if (!enabled) return 0;
    if (productRate != null && productRate > 0) return productRate;
    for (final slab in slabs) {
      if (slab.upToPrice == null || unitPrice <= slab.upToPrice!) {
        return slab.ratePercent;
      }
    }
    return slabs.isEmpty ? 0 : slabs.last.ratePercent;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'pricesIncludeTax': pricesIncludeTax,
    'slabs': slabs.map((s) => s.toJson()).toList(),
    'defaultHsnCode': defaultHsnCode,
  };

  factory GstSettings.fromJson(Map<String, dynamic> json) {
    final rawSlabs = json['slabs'] as List<dynamic>?;
    return GstSettings(
      enabled: json['enabled'] as bool? ?? true,
      pricesIncludeTax: json['pricesIncludeTax'] as bool? ?? true,
      slabs: rawSlabs == null || rawSlabs.isEmpty
          ? GstSettings.defaultApparelSlabs
          : rawSlabs
                .map((s) => GstSlab.fromJson(s as Map<String, dynamic>))
                .toList(),
      defaultHsnCode: json['defaultHsnCode'] as String? ?? '6109',
    );
  }

  static GstSettings decode(String source) =>
      GstSettings.fromJson(jsonDecode(source) as Map<String, dynamic>);
  String encode() => jsonEncode(toJson());
}

/// The tax worked out for a single invoice line.
class GstLineTax {
  const GstLineTax({
    required this.taxableValue,
    required this.taxAmount,
    required this.ratePercent,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  /// Value the tax is charged on — the line total net of GST.
  final double taxableValue;
  final double taxAmount;
  final double ratePercent;
  final double cgst;
  final double sgst;
  final double igst;

  /// What the customer pays for this line.
  double get grossValue => taxableValue + taxAmount;
}

/// Splits a line's tax between the heads.
///
/// A sale inside the seller's own state is CGST + SGST, half the rate each.
/// A sale to another state is a single IGST charge at the full rate. Missing
/// buyer state is treated as intra-state, which is the correct default for a
/// walk-in counter sale.
GstLineTax computeLineTax({
  required double lineTotal,
  required double ratePercent,
  required bool priceIncludesTax,
  required bool interState,
}) {
  if (ratePercent <= 0 || lineTotal == 0) {
    return GstLineTax(
      taxableValue: lineTotal,
      taxAmount: 0,
      ratePercent: 0,
      cgst: 0,
      sgst: 0,
      igst: 0,
    );
  }

  final double taxableValue;
  final double taxAmount;
  if (priceIncludesTax) {
    taxableValue = lineTotal * 100 / (100 + ratePercent);
    taxAmount = lineTotal - taxableValue;
  } else {
    taxableValue = lineTotal;
    taxAmount = lineTotal * ratePercent / 100;
  }

  return GstLineTax(
    taxableValue: _round(taxableValue),
    taxAmount: _round(taxAmount),
    ratePercent: ratePercent,
    cgst: interState ? 0 : _round(taxAmount / 2),
    sgst: interState ? 0 : _round(taxAmount / 2),
    igst: interState ? _round(taxAmount) : 0,
  );
}

double _round(double value) => (value * 100).roundToDouble() / 100;

/// State codes as used in the first two digits of a GSTIN.
const Map<String, String> indianStateCodes = {
  '01': 'Jammu and Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra and Nagar Haveli and Daman and Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
};

/// The state code carried in the first two characters of a GSTIN.
String? stateCodeFromGstin(String? gstin) {
  final value = gstin?.trim() ?? '';
  if (value.length < 2) return null;
  final code = value.substring(0, 2);
  return indianStateCodes.containsKey(code) ? code : null;
}

/// Structural check only — 15 characters, `NN AAAAANNNNA NZN`. It confirms the
/// shape a GSTIN must have; it does not prove the number is registered.
bool isValidGstinFormat(String? gstin) {
  final value = gstin?.trim().toUpperCase() ?? '';
  if (value.length != 15) return false;
  if (!RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$',
  ).hasMatch(value)) {
    return false;
  }
  return indianStateCodes.containsKey(value.substring(0, 2));
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../features/pos/data/invoice_document.dart';
import '../theme/app_colors.dart';
import '../theme/brand_theme.dart';
import '../utils/formatters.dart';
import 'gst.dart';
import 'held_bills.dart';
import 'permissions.dart';
import 'printer_service.dart';
import 'reports.dart';
import 'returns_and_shifts.dart';
import 'statements.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.isActive = true,
    this.grantedPermissions,
  });
  final int id;
  final String name;
  final String username;
  final AppRole role;
  final bool isActive;

  /// What the owner ticked for this person specifically. Null means nobody has
  /// customised the account, so the role decides — which is what every account
  /// created before per-user permissions existed does.
  final Set<Permission>? grantedPermissions;

  /// True once the account's permissions have been set by hand, so the staff
  /// screen can say "Custom" rather than implying the role still governs.
  bool get hasCustomPermissions => grantedPermissions != null;

  Set<Permission> get permissions => grantedPermissions ?? permissionsFor(role);
  bool can(Permission permission) => permissions.contains(permission);
}

class StoreProfile {
  const StoreProfile({
    required this.storeName,
    required this.currencySymbol,
    this.logoPath,
    this.brandImagePath,
    this.subtitle = "MEN'S FASHION STORE",
    this.address,
    this.phone,
    this.email,
    this.taxRegistrationNumber,
    this.receiptFooterText,
    this.receiptNumberPrefix = '',
    this.gstin,
    this.stateCode,
    this.currencyLocale = 'en_IN',
    this.tagline = '',
    this.termsText = '',
    this.declarationText = '',
    this.bankDetails = '',
    this.jurisdiction = '',
    this.brandTheme = BrandTheme.classic,
  });

  /// What a fresh installation starts from.
  ///
  /// The same build runs in more than one shop, so nothing here is baked into
  /// the code that prints the bill — these are only the values the setup screen
  /// opens with, and every one of them is editable under Settings. A second
  /// shop types over them; changing what a new installation starts from is a
  /// matter of editing this one constant.
  static const firstRunDefaults = StoreProfile(
    storeName: 'CLASSY CLOSET',
    currencySymbol: '₹',
    address: 'Shop no. 101, 1st Floor, Mansarovar Plaza, Jaipur',
    gstin: '08KGDPK6891Q1Z8',
    stateCode: '08',
    receiptNumberPrefix: 'CC',
    subtitle: "MEN'S FASHION STORE",
    // The logo already carries "Men's Fashion Store", so the tagline is only
    // the half the artwork does not say.
    tagline: 'Look Classy, Feel Content',
    receiptFooterText: 'Thank you for shopping with us.',
    termsText:
        'Exchange within 7 days with the bill. '
        'No exchange on altered or washed garments.',
    declarationText:
        'We declare that this invoice shows the actual price of the goods '
        'described and that all particulars are true and correct.',
    jurisdiction: 'Subject to Jaipur jurisdiction',
  );

  final String storeName;
  final String currencySymbol;

  /// The receipt logo printed on the thermal bill. Kept small and mono for the
  /// print head to render cleanly. What lands under Settings → Printing.
  final String? logoPath;

  /// The brand mark shown on the login panel, the rail and the app title bar.
  /// A full-colour image is fine here; the print path stays with [logoPath].
  final String? brandImagePath;

  /// The small line under the shop name on the login card and the rail's
  /// wordmark. The logo already carries the shop's category, so this is the
  /// half the artwork does not say.
  final String subtitle;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxRegistrationNumber;
  final String? receiptFooterText;
  final String receiptNumberPrefix;

  /// The shop's own GST number. Printing it is what turns a receipt into a tax
  /// invoice under Rule 46.
  final String? gstin;

  /// Place of supply for the shop. Compared against the buyer's state to decide
  /// between CGST+SGST and IGST.
  final String? stateCode;
  final String currencyLocale;

  /// The line under the shop name on the bill — what the shop sells and why
  /// someone should come back.
  final String tagline;

  /// The exchange policy, printed at the foot of every bill. This is the line a
  /// customer argues with a week later, so the shop must be able to word it.
  final String termsText;

  /// The declaration a tax invoice carries on a full sheet.
  final String declarationText;

  /// Account details for a business buyer paying by transfer.
  final String bankDetails;

  /// "Subject to <city> jurisdiction".
  final String jurisdiction;

  /// The colour palette everything paints against. Ships with a small set of
  /// named combos plus a custom entry where the owner picks two colours. A
  /// second shop can rebrand in one sitting from Settings without a rebuild.
  final BrandTheme brandTheme;

  /// Falls back to the state code embedded in the GSTIN when none was entered.
  String? get effectiveStateCode =>
      (stateCode != null && stateCode!.trim().isNotEmpty)
      ? stateCode!.trim()
      : stateCodeFromGstin(gstin);

  bool get hasGstin => isValidGstinFormat(gstin);

  Map<String, dynamic> toJson() => {
    'storeName': storeName,
    'currencySymbol': currencySymbol,
    'logoPath': logoPath,
    'brandImagePath': brandImagePath,
    'subtitle': subtitle,
    'address': address,
    'phone': phone,
    'email': email,
    'taxRegistrationNumber': taxRegistrationNumber,
    'receiptFooterText': receiptFooterText,
    'receiptNumberPrefix': receiptNumberPrefix,
    'gstin': gstin,
    'stateCode': stateCode,
    'currencyLocale': currencyLocale,
    'tagline': tagline,
    'termsText': termsText,
    'declarationText': declarationText,
    'bankDetails': bankDetails,
    'jurisdiction': jurisdiction,
    'brandTheme': brandTheme.toJson(),
  };

  factory StoreProfile.fromJson(Map<String, dynamic> json) => StoreProfile(
    storeName: (json['storeName'] as String? ?? '').trim(),
    currencySymbol: (json['currencySymbol'] as String? ?? '₹').trim(),
    logoPath: json['logoPath'] as String?,
    brandImagePath: json['brandImagePath'] as String?,
    subtitle: (json['subtitle'] as String? ?? "MEN'S FASHION STORE").trim(),
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    taxRegistrationNumber: json['taxRegistrationNumber'] as String?,
    receiptFooterText: json['receiptFooterText'] as String?,
    receiptNumberPrefix: (json['receiptNumberPrefix'] as String? ?? '').trim(),
    gstin: (json['gstin'] as String?)?.trim(),
    stateCode: (json['stateCode'] as String?)?.trim(),
    currencyLocale: (json['currencyLocale'] as String? ?? 'en_IN').trim(),
    tagline: (json['tagline'] as String? ?? '').trim(),
    termsText: (json['termsText'] as String? ?? '').trim(),
    declarationText: (json['declarationText'] as String? ?? '').trim(),
    bankDetails: (json['bankDetails'] as String? ?? '').trim(),
    jurisdiction: (json['jurisdiction'] as String? ?? '').trim(),
    brandTheme: BrandTheme.fromJson(json['brandTheme']),
  );

  StoreProfile copyWith({
    String? storeName,
    String? currencySymbol,
    String? logoPath,
    bool clearLogoPath = false,
    String? brandImagePath,
    bool clearBrandImagePath = false,
    String? subtitle,
    String? address,
    String? phone,
    String? email,
    String? taxRegistrationNumber,
    String? receiptFooterText,
    String? receiptNumberPrefix,
    String? gstin,
    String? stateCode,
    String? currencyLocale,
    String? tagline,
    String? termsText,
    String? declarationText,
    String? bankDetails,
    String? jurisdiction,
    BrandTheme? brandTheme,
  }) => StoreProfile(
    storeName: storeName ?? this.storeName,
    currencySymbol: currencySymbol ?? this.currencySymbol,
    logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
    brandImagePath: clearBrandImagePath
        ? null
        : (brandImagePath ?? this.brandImagePath),
    subtitle: subtitle ?? this.subtitle,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    taxRegistrationNumber: taxRegistrationNumber ?? this.taxRegistrationNumber,
    receiptFooterText: receiptFooterText ?? this.receiptFooterText,
    receiptNumberPrefix: receiptNumberPrefix ?? this.receiptNumberPrefix,
    gstin: gstin ?? this.gstin,
    stateCode: stateCode ?? this.stateCode,
    currencyLocale: currencyLocale ?? this.currencyLocale,
    tagline: tagline ?? this.tagline,
    termsText: termsText ?? this.termsText,
    declarationText: declarationText ?? this.declarationText,
    bankDetails: bankDetails ?? this.bankDetails,
    jurisdiction: jurisdiction ?? this.jurisdiction,
    brandTheme: brandTheme ?? this.brandTheme,
  );
}

/// A design and the size/colour run underneath it.
class StyleRecord {
  StyleRecord({
    required this.id,
    required this.styleCode,
    required this.name,
    this.description = '',
    this.category = '',
    this.brand = '',
    this.unit = 'pcs',
    this.supplier = '',
    this.hsnCode = '',
    this.season = '',
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.active = true,
    List<ProductRecord>? variants,
  }) : variants = variants ?? <ProductRecord>[];

  final int id;
  final String styleCode;
  final String name;
  final String description;
  final String category;
  final String brand;
  final String unit;
  final String supplier;
  final String hsnCode;
  final String season;
  final double purchasePrice;
  final double sellingPrice;
  final bool active;
  final List<ProductRecord> variants;

  double get totalStock => variants.fold(0.0, (sum, v) => sum + v.stock);
  double get stockValue => variants.fold(0.0, (sum, v) => sum + v.stockValue);

  /// Distinct sizes in the order they were entered, for the matrix columns.
  List<String> get sizes => _distinct(variants.map((v) => v.size));

  /// Distinct colours, for the matrix rows.
  List<String> get colors => _distinct(variants.map((v) => v.color));

  ProductRecord? variantAt(String color, String size) {
    for (final v in variants) {
      if (v.color == color && v.size == size) return v;
    }
    return null;
  }

  static List<String> _distinct(Iterable<String> values) {
    final seen = <String>[];
    for (final value in values) {
      if (!seen.contains(value)) seen.add(value);
    }
    return seen;
  }
}

class ProductRecord {
  ProductRecord({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.brand,
    required this.unit,
    required this.stock,
    required this.minimumStock,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.barcode,
    required this.location,
    this.description = '',
    this.supplier = '',
    this.supplierId,
    this.wholesalePrice = 0,
    this.taxRate = 0,
    this.maximumStock,
    this.expiryDate,
    this.active = true,
    this.styleId,
    this.size = '',
    this.color = '',
    this.hsnCode = '',
    this.imagePath,
  });

  final int id;
  final String sku;
  final String name;
  final String category;
  final String brand;
  final String unit;
  double stock;
  final double minimumStock;
  final double purchasePrice;
  final double sellingPrice;
  final String barcode;
  final String location;
  final String description;
  final String supplier;
  final int? supplierId;
  final double wholesalePrice;
  final double taxRate;
  final double? maximumStock;
  final DateTime? expiryDate;
  final bool active;

  /// Set when this unit is one cell of a style's size/colour matrix.
  final int? styleId;
  final String size;
  final String color;
  final String hsnCode;

  /// Primary image, copied into the app's own folder so it survives the
  /// original file being moved or deleted.
  final String? imagePath;

  double get stockValue => stock * purchasePrice;
  bool get lowStock => stock <= minimumStock;

  /// "Blue / M", or empty for a standalone product.
  String get variantLabel =>
      [color, size].where((v) => v.trim().isNotEmpty).join(' / ');

  /// Name with the variant appended, for the cart and the invoice.
  String get displayName =>
      variantLabel.isEmpty ? name : '$name ($variantLabel)';
}

class CustomerRecord {
  CustomerRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.creditLimit,
    required this.openingBalance,
    required this.balance,
    this.gstin = '',
    this.stateCode = '',
    this.lifetimeSpend = 0,
    this.lifetimeBills = 0,
    this.lastPurchaseAt,
  });
  final int id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final double creditLimit;
  final double openingBalance;
  double balance;

  /// Everything this customer has ever spent here, across every bill since the
  /// shop opened. Counted from the bills themselves rather than kept as a
  /// running figure, so it can never drift out of step with them.
  final double lifetimeSpend;

  /// How many bills that was.
  final int lifetimeBills;

  /// When they were last in. Null for someone who has an account but has not
  /// bought under it yet.
  final DateTime? lastPurchaseAt;

  /// Average bill, for the customers screen. Zero for a customer with no
  /// bills rather than a division by zero.
  double get averageBill =>
      lifetimeBills == 0 ? 0 : lifetimeSpend / lifetimeBills;

  /// Present for registered buyers who need the invoice in their own name.
  final String gstin;
  final String stateCode;

  String? get effectiveStateCode => stateCode.trim().isNotEmpty
      ? stateCode.trim()
      : stateCodeFromGstin(gstin);
}

class SupplierRecord {
  SupplierRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.openingBalance,
    required this.balance,
  });
  final int id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final double openingBalance;
  double balance;
}

class SaleRecord {
  SaleRecord({
    required this.receipt,
    required this.customerName,
    required this.total,
    required this.profit,
    required this.createdAt,
    this.taxableValue = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.discountTotal = 0,
    this.paymentMethod = 'cash',
    this.cashAmount = 0,
    this.cardAmount = 0,
    this.upiAmount = 0,
    this.customerGstin,
    this.placeOfSupply,
  });
  final String receipt;
  final String customerName;
  final double total;
  final double profit;
  final DateTime createdAt;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final double discountTotal;
  final String paymentMethod;
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final String? customerGstin;
  final String? placeOfSupply;

  double get taxTotal => cgst + sgst + igst;
  bool get isInterState => igst > 0;
}

class CartLine {
  CartLine({required this.product, required this.quantity, this.discount = 0});

  /// Re-pointed by [RetailStore._relinkCart] after a refresh, because the
  /// catalogue is rebuilt from scratch and a bill must not keep quoting a
  /// price or a stock level that has since moved.
  ProductRecord product;
  int quantity;

  /// Flat amount taken off this line, not a percentage.
  double discount;

  double get gross => quantity * product.sellingPrice;

  /// What the customer pays for this line, discount applied.
  double get total => (gross - discount).clamp(0, double.infinity).toDouble();
  double get cost => quantity * product.purchasePrice;
}

/// Aggregated sales figures for one period.
class SalesSummary {
  const SalesSummary({
    required this.total,
    required this.profit,
    required this.tax,
    required this.cash,
    required this.card,
    required this.upi,
    required this.count,
  });

  final double total;
  final double profit;
  final double tax;
  final double cash;
  final double card;
  final double upi;
  final int count;

  static const empty = SalesSummary(
    total: 0,
    profit: 0,
    tax: 0,
    cash: 0,
    card: 0,
    upi: 0,
    count: 0,
  );

  double get averageBill => count == 0 ? 0 : total / count;
  double get marginPercent => total == 0 ? 0 : profit / total * 100;
}

class RetailStore extends ChangeNotifier {
  RetailStore(this._db);

  static const storeProfileKey = 'store_profile';
  static const gstSettingsKey = 'gst_settings';
  static const printerSettingsKey = 'printer_settings';
  static const invoiceCounterKey = 'invoice_counter';

  final AppDatabase _db;
  AppUser? currentUser;
  StoreProfile? storeProfile;
  GstSettings gstSettings = const GstSettings();
  PrinterSettings printerSettings = const PrinterSettings();
  final products = <ProductRecord>[];
  final styles = <StyleRecord>[];
  final customers = <CustomerRecord>[];
  final suppliers = <SupplierRecord>[];
  final categoryNames = <String>[];
  final brandNames = <String>[];
  final unitNames = <String>[];
  final sizeNames = <String>[];
  final colorNames = <String>[];
  final sales = <SaleRecord>[];
  final cart = <CartLine>[];
  final auditLogs = <String>[];
  final _styleRows = <ProductStyleRow>[];
  bool _initialized = false;

  /// A search handed off from the top bar to the page that can answer it.
  ///
  /// The handoff is addressed: the route the query is meant for travels with
  /// the query itself. Without that, every mounted page raced to claim it and
  /// whichever one happened to be on screen swallowed the query a moment
  /// before the navigation to the real destination — so the shopkeeper landed
  /// on the right page with an empty box, which is what "the search does
  /// nothing" looked like from the counter.
  ///
  /// Addressing it also means a page that is *already* open picks the query up
  /// on the spot, instead of only ever reading it once in `initState` and
  /// therefore ignoring every search after the first.
  String _pendingSearchQuery = '';
  String _pendingSearchRoute = '';

  String get pendingGlobalQuery => _pendingSearchQuery;

  /// Sends [query] to the page at [route]. Call this *before* navigating: a
  /// page already showing [route] claims it from the notification, and a page
  /// about to be built claims it from [takeSearchFor] instead.
  void requestSearch(String query, String route) {
    _pendingSearchQuery = query.trim();
    _pendingSearchRoute = route;
    notifyListeners();
  }

  /// Claims a pending search, but only one addressed to [route]. Returns an
  /// empty string when there is nothing waiting for this page, which is the
  /// signal to leave the page's own search box exactly as the user left it.
  String takeSearchFor(String route) {
    if (_pendingSearchRoute != route || _pendingSearchQuery.isEmpty) return '';
    final query = _pendingSearchQuery;
    _pendingSearchQuery = '';
    _pendingSearchRoute = '';
    return query;
  }

  bool get isAuthenticated => currentUser != null;
  bool get hasStoreProfile =>
      storeProfile != null && storeProfile!.storeName.trim().isNotEmpty;
  String get displayStoreName =>
      hasStoreProfile ? storeProfile!.storeName : 'Store Setup';
  double get todaySales =>
      sales.where(_today).fold(0, (sum, sale) => sum + sale.total);
  double get todayProfit =>
      sales.where(_today).fold(0, (sum, sale) => sum + sale.profit);
  double get inventoryValue =>
      products.fold(0, (sum, product) => sum + product.stockValue);
  Iterable<ProductRecord> get lowStockProducts =>
      products.where((product) => product.lowStock);
  Iterable<CustomerRecord> get pendingCustomers =>
      customers.where((customer) => customer.balance > 0);

  /// Totals for an arbitrary window, so the dashboard and reports can ask for
  /// today, this week or this month without each rolling their own loop.
  SalesSummary summaryBetween(DateTime from, DateTime to) {
    var total = 0.0, profit = 0.0, tax = 0.0, cash = 0.0, card = 0.0, upi = 0.0;
    var count = 0;
    for (final sale in sales) {
      if (sale.createdAt.isBefore(from) || !sale.createdAt.isBefore(to)) {
        continue;
      }
      total += sale.total;
      profit += sale.profit;
      tax += sale.taxTotal;
      cash += sale.cashAmount;
      card += sale.cardAmount;
      upi += sale.upiAmount;
      count++;
    }
    return SalesSummary(
      total: total,
      profit: profit,
      tax: tax,
      cash: cash,
      card: card,
      upi: upi,
      count: count,
    );
  }

  SalesSummary get todaySummary {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return summaryBetween(start, start.add(const Duration(days: 1)));
  }

  SalesSummary get weekSummary {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    return summaryBetween(start, today.add(const Duration(days: 1)));
  }

  SalesSummary get monthSummary {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    return summaryBetween(start, DateTime(now.year, now.month + 1));
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _seedFirstRunData();
    await refresh();
    _initialized = true;
  }

  Future<void> refresh() async {
    await Future.wait([
      _loadStoreProfile(),
      _loadGstSettings(),
      _loadPrinterSettings(),
      _loadLookups(),
      _loadSuppliers(),
      _loadProducts(),
      _loadCustomers(),
      _loadSales(),
      _loadAuditLogs(),
      _loadUsers(),
      _loadReturns(),
      _loadPurchases(),
      _loadExpenses(),
    ]);
    // Shifts read the user list, payments read the party lists and stock counts
    // read the catalogue, so all three load after those rather than alongside.
    await _loadShifts();
    await _loadPartyPayments();
    await _loadHeldBills();
    _rebuildStyles();
    _relinkCart();
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final row =
        await (_db.select(_db.users)..where(
              (u) => u.username.equals(normalized) & u.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (row == null || row.passwordHash != _hash(password)) return false;
    final role = await (_db.select(
      _db.roles,
    )..where((r) => r.id.equals(row.roleId))).getSingleOrNull();
    currentUser = AppUser(
      id: row.id,
      name: row.fullName,
      username: row.username,
      role: _roleFromName(role?.name),
      grantedPermissions: (await _grantedPermissions())[row.id],
    );
    await _audit('AUTH', 'users', row.id, 'Signed in as $normalized');
    notifyListeners();
    return true;
  }

  /// Whether the signed-in user may do [permission].
  ///
  /// No one signed in means no, so a guard that runs before login fails closed.
  bool can(Permission permission) => currentUser?.can(permission) ?? false;

  /// Everyone with a login, for the staff screen.
  final users = <AppUser>[];

  Future<void> _loadUsers() async {
    final roles = {
      for (final r in await _db.select(_db.roles).get()) r.id: r.name,
    };
    final granted = await _grantedPermissions();
    final rows = await _db.select(_db.users).get();
    users
      ..clear()
      ..addAll(
        rows.map(
          (u) => AppUser(
            id: u.id,
            name: u.fullName,
            username: u.username,
            role: AppRole.fromName(roles[u.roleId]),
            isActive: u.isActive,
            grantedPermissions: granted[u.id],
          ),
        ),
      );

    // The signed-in user's own rights can be changed while they are signed in
    // — by themselves, or by an owner at another till — so the live copy is
    // refreshed from the same read rather than left as it was at login.
    final signedIn = currentUser;
    if (signedIn != null) {
      currentUser = users.where((u) => u.id == signedIn.id).firstOrNull;
    }
  }

  /// Per-user permission overrides, keyed by user. A user absent from the map
  /// has never been customised and falls back to their role.
  Future<Map<int, Set<Permission>>> _grantedPermissions() async {
    final byName = {for (final p in Permission.values) p.name: p};
    final granted = <int, Set<Permission>>{};
    for (final row in await _db.select(_db.userPermissions).get()) {
      // An empty set is meaningful — it says "this person may do nothing" —
      // so the entry is created even when the code no longer resolves.
      final set = granted.putIfAbsent(row.userId, () => <Permission>{});
      final permission = byName[row.code];
      if (permission != null) set.add(permission);
    }
    return granted;
  }

  /// Replaces one staff member's permissions.
  ///
  /// Passing null hands the account back to its role. Passing a set — even an
  /// empty one — pins it, and the role becomes a label rather than a rule.
  Future<String?> saveUserPermissions(
    int userId,
    Set<Permission>? permissions,
  ) async {
    final user = users.where((u) => u.id == userId).firstOrNull;
    if (user == null) return 'That account could not be found.';

    // Same guard as the role check: the shop must never be able to lock itself
    // out of its own staff screen.
    final effective = permissions ?? permissionsFor(user.role);
    if (!effective.contains(Permission.manageUsers) && user.isActive) {
      final others = users.where(
        (u) => u.id != userId && u.isActive && u.can(Permission.manageUsers),
      );
      if (others.isEmpty) {
        return 'This is the only account that can manage staff. Give someone '
            'else that permission first.';
      }
    }

    await _db.transaction(() async {
      await (_db.delete(
        _db.userPermissions,
      )..where((p) => p.userId.equals(userId))).go();
      if (permissions != null) {
        for (final permission in permissions) {
          await _db
              .into(_db.userPermissions)
              .insert(
                UserPermissionsCompanion.insert(
                  userId: userId,
                  code: permission.name,
                ),
              );
        }
      }
      await _audit(
        'UPDATE',
        'users',
        userId,
        permissions == null
            ? 'Reset ${user.username} to the ${user.role.label} role\'s '
                  'permissions'
            : 'Set ${user.username} to ${permissions.length} permission(s)',
      );
    });
    await refresh();
    return null;
  }

  /// Creates or updates a staff account.
  ///
  /// [password] is only applied when non-empty, so editing someone's name or
  /// role does not silently reset the password they are using.
  Future<String?> saveUser({
    required int id,
    required String fullName,
    required String username,
    required AppRole role,
    String password = '',
    bool isActive = true,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.length < 3) return 'Username must be at least 3 characters.';
    if (fullName.trim().isEmpty) return 'Enter a full name.';
    if (id == 0 && password.trim().length < 4) {
      return 'Set a password of at least 4 characters.';
    }
    if (password.trim().isNotEmpty && password.trim().length < 4) {
      return 'Password must be at least 4 characters.';
    }

    final clash = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals(normalized))).getSingleOrNull();
    if (clash != null && clash.id != id) {
      return 'That username is already taken.';
    }

    // The shop must never be locked out of its own settings, so the last
    // active admin cannot be demoted or switched off.
    if (id != 0) {
      final admins = users.where(
        (u) => u.role == AppRole.admin && u.isActive && u.id != id,
      );
      final wasAdmin = users
          .where((u) => u.id == id)
          .any((u) => u.role == AppRole.admin && u.isActive);
      final losingAdmin = wasAdmin && (role != AppRole.admin || !isActive);
      if (losingAdmin && admins.isEmpty) {
        return 'This is the only administrator. Make someone else an '
            'administrator first.';
      }
    }

    final roleId = await _ensureRole(role);
    if (id == 0) {
      final newId = await _db
          .into(_db.users)
          .insert(
            UsersCompanion.insert(
              fullName: fullName.trim(),
              username: normalized,
              passwordHash: _hash(password.trim()),
              roleId: roleId,
              isActive: Value(isActive),
            ),
          );
      await _audit('CREATE', 'users', newId, 'Added ${role.label} $normalized');
    } else {
      await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(
          fullName: Value(fullName.trim()),
          username: Value(normalized),
          roleId: Value(roleId),
          isActive: Value(isActive),
        ),
      );
      if (password.trim().isNotEmpty) {
        await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
          UsersCompanion(passwordHash: Value(_hash(password.trim()))),
        );
        await _audit('UPDATE', 'users', id, 'Reset password for $normalized');
      }
      await _audit('UPDATE', 'users', id, 'Updated $normalized');
    }
    await refresh();
    return null;
  }

  /// Lets the signed-in user change their own password after proving the old
  /// one, which is how the seeded admin credentials get retired.
  Future<String?> changeOwnPassword(String current, String next) async {
    final user = currentUser;
    if (user == null) return 'Not signed in.';
    if (next.trim().length < 4) {
      return 'New password must be at least 4 characters.';
    }
    final row = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(user.id))).getSingleOrNull();
    if (row == null || row.passwordHash != _hash(current)) {
      return 'Current password is not correct.';
    }
    await (_db.update(_db.users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(passwordHash: Value(_hash(next.trim()))),
    );
    await _audit('UPDATE', 'users', user.id, 'Changed own password');
    return null;
  }

  /// True while the seeded credentials still work, so the app can nag until
  /// they are changed.
  Future<bool> usingDefaultAdminPassword() async {
    final row = await (_db.select(
      _db.users,
    )..where((u) => u.username.equals('admin'))).getSingleOrNull();
    return row != null && row.passwordHash == _hash('admin123');
  }

  Future<int> _ensureRole(AppRole role) async {
    final existing = await (_db.select(
      _db.roles,
    )..where((r) => r.name.equals(role.label))).getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.roles)
        .insert(
          RolesCompanion.insert(
            name: role.label,
            description: Value(role.description),
          ),
        );
  }

  Future<void> logout() async {
    await _audit('AUTH', 'users', currentUser?.id, 'Signed out');
    currentUser = null;
    notifyListeners();
  }

  Future<String?> copyLogoToAppFolder(String? sourcePath) =>
      _copyBrandImage(sourcePath, base: 'store_logo');

  /// The larger brand image shown on the login card and in the rail. Kept in
  /// the app's own folder so a shop that moves or deletes the source file
  /// still sees its mark. Same shape as [copyLogoToAppFolder] — split so the
  /// two files land under different names.
  Future<String?> copyBrandImageToAppFolder(String? sourcePath) =>
      _copyBrandImage(sourcePath, base: 'brand_image');

  Future<String?> _copyBrandImage(
    String? sourcePath, {
    required String base,
  }) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath);
    if (!source.existsSync()) return sourcePath;
    final directory = await _appDataDirectory();
    final extension = p.extension(source.path).isEmpty
        ? '.png'
        : p.extension(source.path);
    final target = File(p.join(directory.path, '$base$extension'));
    await source.copy(target.path);
    return target.path;
  }

  Future<void> saveStoreProfile(StoreProfile profile) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: storeProfileKey,
            valueJson: jsonEncode(profile.toJson()),
          ),
        );
    storeProfile = profile;
    await _audit(
      'UPSERT',
      'settings',
      null,
      'Saved store profile for ${profile.storeName}',
    );
    notifyListeners();
  }

  Future<int> saveProduct(ProductRecord product) async {
    late int productId;
    await _db.transaction(() async {
      final unitId = await _ensureUnit(product.unit);
      final categoryId = await _ensureCategory(product.category);
      final brandId = await _ensureBrand(product.brand);
      final supplierId = product.supplier.trim().isEmpty
          ? null
          : await _ensureSupplier(product.supplier);
      final companion = ProductsCompanion(
        sku: Value(product.sku),
        barcode: Value(
          product.barcode.trim().isEmpty ? null : product.barcode.trim(),
        ),
        name: Value(product.name),
        description: Value(
          product.description.trim().isEmpty
              ? null
              : product.description.trim(),
        ),
        categoryId: Value(categoryId),
        brandId: Value(brandId),
        unitId: Value(unitId),
        supplierId: Value(supplierId),
        purchasePrice: Value(product.purchasePrice),
        sellingPrice: Value(product.sellingPrice),
        wholesalePrice: Value(product.wholesalePrice),
        taxRate: Value(product.taxRate),
        currentStock: Value(product.stock.clamp(0, double.infinity).toDouble()),
        minimumStock: Value(product.minimumStock),
        maximumStock: Value(product.maximumStock),
        location: Value(
          product.location.trim().isEmpty ? null : product.location.trim(),
        ),
        expiryDate: Value(product.expiryDate),
        isActive: Value(product.active),
        styleId: Value(product.styleId),
        size: Value(product.size.trim().isEmpty ? null : product.size.trim()),
        color: Value(
          product.color.trim().isEmpty ? null : product.color.trim(),
        ),
        hsnCode: Value(
          product.hsnCode.trim().isEmpty ? null : product.hsnCode.trim(),
        ),
      );
      if (product.id == 0) {
        productId = await _db.into(_db.products).insert(companion);
        final openingStock = product.stock.clamp(0, double.infinity).toDouble();
        if (openingStock != 0) {
          await _db
              .into(_db.inventoryMovements)
              .insert(
                InventoryMovementsCompanion.insert(
                  productId: productId,
                  movementType: 'opening',
                  quantity: openingStock,
                  referenceType: const Value('products'),
                  referenceId: Value(productId),
                ),
              );
        }
        await _audit(
          'CREATE',
          'products',
          productId,
          'Created ${product.sku} ${product.name}',
        );
      } else {
        productId = product.id;
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(product.id))).write(companion);
        await _audit(
          'UPDATE',
          'products',
          product.id,
          'Updated ${product.sku} ${product.name}',
        );
      }
    });
    await refresh();
    return productId;
  }

  Future<void> addProduct(ProductRecord product) async {
    await saveProduct(product);
  }

  Future<void> deleteProduct(int id) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(isActive: Value(false), currentStock: Value(0)),
    );
    await _audit('DELETE', 'products', id, 'Deactivated product $id');
    await refresh();
  }

  Future<void> deleteStyle(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.productStyles)..where((s) => s.id.equals(id)))
          .write(const ProductStylesCompanion(isActive: Value(false)));
      await (_db.update(
        _db.products,
      )..where((p) => p.styleId.equals(id))).write(
        const ProductsCompanion(isActive: Value(false), currentStock: Value(0)),
      );
      await _audit('DELETE', 'product_styles', id, 'Deactivated style $id');
    });
    await refresh();
  }

  /// Saves a design together with its whole size/colour run in one transaction.
  ///
  /// [variants] is the complete intended matrix. Cells that already exist are
  /// updated, new cells are inserted, and cells the user cleared are
  /// deactivated rather than deleted so historical sale lines keep resolving.
  Future<int> saveStyle(
    StyleRecord style, {
    required List<ProductRecord> variants,
  }) async {
    late int styleId;
    await _db.transaction(() async {
      final unitId = await _ensureUnit(style.unit);
      final categoryId = await _ensureCategory(style.category);
      final brandId = await _ensureBrand(style.brand);
      final supplierId = style.supplier.trim().isEmpty
          ? null
          : await _ensureSupplier(style.supplier);

      final companion = ProductStylesCompanion(
        styleCode: Value(style.styleCode.trim()),
        name: Value(style.name.trim()),
        description: Value(
          style.description.trim().isEmpty ? null : style.description.trim(),
        ),
        categoryId: Value(categoryId),
        brandId: Value(brandId),
        unitId: Value(unitId),
        supplierId: Value(supplierId),
        hsnCode: Value(
          style.hsnCode.trim().isEmpty ? null : style.hsnCode.trim(),
        ),
        season: Value(style.season.trim().isEmpty ? null : style.season.trim()),
        purchasePrice: Value(style.purchasePrice),
        sellingPrice: Value(style.sellingPrice),
        isActive: Value(style.active),
      );

      if (style.id == 0) {
        styleId = await _db.into(_db.productStyles).insert(companion);
        await _audit(
          'CREATE',
          'product_styles',
          styleId,
          'Created style ${style.styleCode} ${style.name}',
        );
      } else {
        styleId = style.id;
        await (_db.update(
          _db.productStyles,
        )..where((s) => s.id.equals(styleId))).write(companion);
        await _audit(
          'UPDATE',
          'product_styles',
          styleId,
          'Updated style ${style.styleCode} ${style.name}',
        );
      }

      final existing = await (_db.select(
        _db.products,
      )..where((p) => p.styleId.equals(styleId))).get();
      final keptIds = <int>{};

      for (final variant in variants) {
        final match = existing
            .where(
              (row) =>
                  (row.size ?? '') == variant.size &&
                  (row.color ?? '') == variant.color,
            )
            .firstOrNull;

        final row = ProductsCompanion(
          styleId: Value(styleId),
          size: Value(variant.size.trim().isEmpty ? null : variant.size.trim()),
          color: Value(
            variant.color.trim().isEmpty ? null : variant.color.trim(),
          ),
          sku: Value(variant.sku.trim()),
          barcode: Value(
            variant.barcode.trim().isEmpty ? null : variant.barcode.trim(),
          ),
          name: Value(style.name.trim()),
          description: Value(
            style.description.trim().isEmpty ? null : style.description.trim(),
          ),
          categoryId: Value(categoryId),
          brandId: Value(brandId),
          unitId: Value(unitId),
          supplierId: Value(supplierId),
          hsnCode: Value(
            style.hsnCode.trim().isEmpty ? null : style.hsnCode.trim(),
          ),
          purchasePrice: Value(variant.purchasePrice),
          sellingPrice: Value(variant.sellingPrice),
          taxRate: Value(variant.taxRate),
          currentStock: Value(
            variant.stock.clamp(0, double.infinity).toDouble(),
          ),
          minimumStock: Value(variant.minimumStock),
          location: Value(
            variant.location.trim().isEmpty ? null : variant.location.trim(),
          ),
          isActive: const Value(true),
        );

        if (match == null) {
          final id = await _db.into(_db.products).insert(row);
          keptIds.add(id);
          final openingStock = variant.stock
              .clamp(0, double.infinity)
              .toDouble();
          if (openingStock != 0) {
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion.insert(
                    productId: id,
                    movementType: 'opening',
                    quantity: openingStock,
                    referenceType: const Value('product_styles'),
                    referenceId: Value(styleId),
                  ),
                );
          }
        } else {
          keptIds.add(match.id);
          await (_db.update(
            _db.products,
          )..where((p) => p.id.equals(match.id))).write(row);
        }
      }

      for (final row in existing) {
        if (keptIds.contains(row.id)) continue;
        await (_db.update(_db.products)..where((p) => p.id.equals(row.id)))
            .write(const ProductsCompanion(isActive: Value(false)));
      }
    });
    await refresh();
    return styleId;
  }

  /// Copies [sourcePath] into the app's own image folder and records it as the
  /// product's primary image. Keeping our own copy means the picture survives
  /// the shopkeeper moving or deleting the original file.
  Future<String?> saveProductImage(int productId, String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) return null;
    final directory = await _appDataDirectory();
    final images = Directory(p.join(directory.path, 'product_images'));
    if (!images.existsSync()) images.createSync(recursive: true);

    final extension = p.extension(source.path).isEmpty
        ? '.png'
        : p.extension(source.path);
    final target = File(
      p.join(
        images.path,
        'product_${productId}_${DateTime.now().millisecondsSinceEpoch}'
        '$extension',
      ),
    );
    await source.copy(target.path);

    await _db.transaction(() async {
      await (_db.update(_db.productImages)
            ..where((i) => i.productId.equals(productId)))
          .write(const ProductImagesCompanion(isPrimary: Value(false)));
      await _db
          .into(_db.productImages)
          .insert(
            ProductImagesCompanion.insert(
              productId: productId,
              filePath: target.path,
              isPrimary: const Value(true),
            ),
          );
    });
    await refresh();
    return target.path;
  }

  /// Every image on file for a product, primary first.
  Future<List<String>> productImages(int productId) async {
    final rows =
        await (_db.select(_db.productImages)
              ..where((i) => i.productId.equals(productId))
              ..orderBy([
                (i) => OrderingTerm.desc(i.isPrimary),
                (i) => OrderingTerm.asc(i.id),
              ]))
            .get();
    return rows.map((r) => r.filePath).toList();
  }

  Future<void> deleteProductImage(String filePath) async {
    await (_db.delete(
      _db.productImages,
    )..where((i) => i.filePath.equals(filePath))).go();
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException {
        // The row is gone either way; a locked file is not worth failing over.
      }
    }
    await refresh();
  }

  Future<int> saveCustomer(CustomerRecord customer) async {
    late int customerId;
    final companion = CustomersCompanion(
      name: Value(customer.name),
      phone: Value(
        customer.phone.trim().isEmpty ? null : customer.phone.trim(),
      ),
      email: Value(
        customer.email.trim().isEmpty ? null : customer.email.trim(),
      ),
      address: Value(
        customer.address.trim().isEmpty ? null : customer.address.trim(),
      ),
      creditLimit: Value(customer.creditLimit),
      openingBalance: Value(customer.openingBalance),
      currentBalance: Value(customer.balance),
      gstin: Value(
        customer.gstin.trim().isEmpty
            ? null
            : customer.gstin.trim().toUpperCase(),
      ),
      stateCode: Value(
        customer.stateCode.trim().isEmpty ? null : customer.stateCode.trim(),
      ),
    );
    if (customer.id == 0) {
      customerId = await _db.into(_db.customers).insert(companion);
      await _audit(
        'CREATE',
        'customers',
        customerId,
        'Created ${customer.name}',
      );
    } else {
      customerId = customer.id;
      await (_db.update(
        _db.customers,
      )..where((c) => c.id.equals(customer.id))).write(companion);
      await _audit(
        'UPDATE',
        'customers',
        customer.id,
        'Updated ${customer.name}',
      );
    }
    await refresh();
    return customerId;
  }

  Future<void> addCustomer(CustomerRecord customer) async {
    await saveCustomer(customer);
  }

  Future<int> saveSupplier(SupplierRecord supplier) async {
    late int supplierId;
    final companion = SuppliersCompanion(
      name: Value(supplier.name),
      phone: Value(
        supplier.phone.trim().isEmpty ? null : supplier.phone.trim(),
      ),
      email: Value(
        supplier.email.trim().isEmpty ? null : supplier.email.trim(),
      ),
      address: Value(
        supplier.address.trim().isEmpty ? null : supplier.address.trim(),
      ),
      openingBalance: Value(supplier.openingBalance),
      currentBalance: Value(supplier.balance),
    );
    if (supplier.id == 0) {
      supplierId = await _db.into(_db.suppliers).insert(companion);
      await _audit(
        'CREATE',
        'suppliers',
        supplierId,
        'Created ${supplier.name}',
      );
    } else {
      supplierId = supplier.id;
      await (_db.update(
        _db.suppliers,
      )..where((s) => s.id.equals(supplier.id))).write(companion);
      await _audit(
        'UPDATE',
        'suppliers',
        supplier.id,
        'Updated ${supplier.name}',
      );
    }
    await refresh();
    return supplierId;
  }

  /// Puts one more of [product] on the bill, or refuses when the rail is
  /// empty.
  ///
  /// Returns false when nothing was added, so the till can say why rather than
  /// appearing to ignore the scan. The cap is what stops stock going negative:
  /// before it, holding the + button on a bill for three shirts happily sold
  /// ten and left the catalogue reading minus seven.
  bool addToCart(ProductRecord product) {
    final existing = cart
        .where((line) => line.product.id == product.id)
        .cast<CartLine?>()
        .firstOrNull;
    final onBill = existing?.quantity ?? 0;
    if (onBill + 1 > product.stock) return false;
    if (existing == null) {
      cart.add(CartLine(product: product, quantity: 1));
    } else {
      existing.quantity++;
    }
    notifyListeners();
    return true;
  }

  /// Sets a line's quantity, capped at what is on the rail. Zero or less takes
  /// the line off the bill.
  void setCartQuantity(CartLine line, int quantity) {
    if (quantity <= 0) {
      removeFromCart(line);
      return;
    }
    final capped = quantity > line.product.stock
        ? line.product.stock.floor()
        : quantity;
    line.quantity = capped < 1 ? 1 : capped;
    notifyListeners();
  }

  /// Points the open bill's lines back at the freshly loaded catalogue.
  ///
  /// [_loadProducts] rebuilds every [ProductRecord], so without this a bill
  /// left on the counter across a refresh keeps quoting the price and the
  /// stock level from before it — and the price it quotes is the price the
  /// customer is charged. A line whose product has since been deactivated
  /// leaves the bill; it can no longer be sold.
  void _relinkCart() {
    if (cart.isEmpty) return;
    final byId = {for (final product in products) product.id: product};
    cart.removeWhere((line) => !byId.containsKey(line.product.id));
    for (final line in cart) {
      line.product = byId[line.product.id]!;
    }
  }

  /// Flat amount taken off the whole bill — "call it 1,800". Held as a scalar
  /// rather than distributed across the lines because the shop wants one
  /// discount figure on the printed bill, not a fragment beside every item.
  /// [checkout] and [cartTotals] apply it to the subtotal before GST is
  /// computed, so the tax printed on the bill is the tax on the net.
  double _billDiscount = 0.0;

  /// The current bill discount, clamped to what the cart is worth so removing
  /// items after typing the discount cannot leave a negative total.
  double get billDiscount => _money(_billDiscount.clamp(0, cartGrossTotal));

  /// Total taken off the cart — per-line discounts (unused today, kept as a
  /// building block) plus the bill-level discount.
  double get cartDiscountTotal =>
      cart.fold(0.0, (sum, line) => sum + line.discount) + billDiscount;

  /// The cart before any discount.
  double get cartGrossTotal => cart.fold(0.0, (sum, line) => sum + line.gross);

  /// Takes a flat rupee amount off a single line. Left in the API as a
  /// building block; the till does not expose it today.
  void setLineDiscount(CartLine line, double amount) {
    line.discount = _money(amount.clamp(0, line.gross));
    notifyListeners();
  }

  /// Takes a flat rupee amount off the whole bill — "the total came to 2,000,
  /// give them 200 off".
  ///
  /// Stored as one number rather than spread across the lines. The old
  /// approach distributed the discount pro-rata onto each line's own discount
  /// so per-line tax stayed reconcilable, but that meant every printed line
  /// carried a "less …" fragment and the bill panel showed the money twice.
  /// The shop reads a bill as "here is what you bought, here is one discount,
  /// here is what you pay", so the discount now sits at bill level, GST is
  /// computed on the discounted net (see [cartTotals]), and the printed lines
  /// stay clean.
  void applyBillDiscount(double amount) {
    _billDiscount = _money(amount.clamp(0, cartGrossTotal));
    notifyListeners();
  }

  /// Clears the bill discount and any per-line discounts.
  void clearDiscounts() {
    _billDiscount = 0;
    for (final line in cart) {
      line.discount = 0;
    }
    notifyListeners();
  }

  void removeFromCart(CartLine line) {
    cart.remove(line);
    // A discount on an empty bill has nothing to reduce; drop it so the next
    // basket starts clean.
    if (cart.isEmpty) _billDiscount = 0;
    notifyListeners();
  }

  /// The GST rate that applies to one unit of [product], honouring an explicit
  /// per-product rate first and the price slabs second.
  double gstRateFor(ProductRecord product) => gstSettings.rateFor(
    unitPrice: product.sellingPrice,
    productRate: product.taxRate,
  );

  /// Tax for a cart line as it would be charged to [customer].
  GstLineTax lineTaxFor(CartLine line, {CustomerRecord? customer}) =>
      computeLineTax(
        lineTotal: line.total,
        ratePercent: gstRateFor(line.product),
        priceIncludesTax: gstSettings.pricesIncludeTax,
        interState: _isInterState(customer),
      );

  /// A sale is inter-state when the buyer's state is known and differs from the
  /// shop's. A walk-in with no state is treated as local.
  bool _isInterState(CustomerRecord? customer) {
    final shopState = storeProfile?.effectiveStateCode;
    final buyerState = customer?.effectiveStateCode;
    if (shopState == null || buyerState == null) return false;
    return shopState != buyerState;
  }

  /// Grand total of the cart as the customer will pay it.
  ///
  /// With tax-inclusive pricing — the Indian retail norm — this is just the
  /// sum of the line totals minus the bill discount, because GST is already
  /// inside the shelf price. With tax-exclusive pricing the tax is added on
  /// top of the discounted taxable value.
  double cartGrandTotal({CustomerRecord? customer}) =>
      cartTotals(customer: customer).total;

  /// Every figure the pinned footer and the checkout arithmetic need, in one
  /// pass.
  ///
  /// The bill discount is applied at the whole-bill level, then the tax is
  /// derived from the discounted net — that is the shape the shopkeeper asked
  /// for. When the cart mixes GST rates the discount is split across the rate
  /// slabs in proportion to their share of the gross, so the arithmetic still
  /// balances line-by-line inside each slab.
  CartTotals cartTotals({CustomerRecord? customer}) {
    if (cart.isEmpty) {
      return const CartTotals(
        gross: 0,
        billDiscount: 0,
        lineDiscount: 0,
        taxable: 0,
        cgst: 0,
        sgst: 0,
        igst: 0,
        total: 0,
      );
    }

    final interState = _isInterState(customer);
    var gross = 0.0;
    var lineDiscount = 0.0;
    final byRate = <double, _RateBasket>{};
    for (final line in cart) {
      gross += line.gross;
      lineDiscount += line.discount;
      final rate = gstRateFor(line.product);
      // A line whose per-line discount is non-zero contributes to the slab at
      // its post-discount value — the per-line discount is the operator's own
      // adjustment, not the bill-level one.
      final basket = byRate.putIfAbsent(rate, _RateBasket.new);
      basket.gross += line.total;
    }

    final billDiscount = _money(_billDiscount.clamp(0, gross - lineDiscount));
    final basketGrossTotal = byRate.values.fold<double>(
      0,
      (sum, b) => sum + b.gross,
    );

    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0, total = 0.0;
    var remaining = billDiscount;
    final entries = byRate.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final rate = entry.key;
      final basket = entry.value;
      // Last slab takes whatever is left of the bill discount, so rounding
      // never leaves a paisa behind or over.
      final share = i == entries.length - 1
          ? remaining
          : _money(billDiscount * basket.gross / basketGrossTotal);
      remaining = _money(remaining - share);
      final slabNet = basket.gross - share;
      final slabTax = computeLineTax(
        lineTotal: slabNet,
        ratePercent: rate,
        priceIncludesTax: gstSettings.pricesIncludeTax,
        interState: interState,
      );
      taxable += slabTax.taxableValue;
      cgst += slabTax.cgst;
      sgst += slabTax.sgst;
      igst += slabTax.igst;
      total += gstSettings.pricesIncludeTax ? slabNet : slabTax.grossValue;
    }

    return CartTotals(
      gross: _money(gross),
      billDiscount: billDiscount,
      lineDiscount: _money(lineDiscount),
      taxable: _money(taxable),
      cgst: _money(cgst),
      sgst: _money(sgst),
      igst: _money(igst),
      total: _money(total),
    );
  }

  Future<SaleRecord> checkout({
    CustomerRecord? customer,
    double paid = 0,
    String paymentMethod = 'cash',
    double cashAmount = 0,
    double cardAmount = 0,
    double upiAmount = 0,
  }) async {
    final snapshot = List<CartLine>.from(cart);
    if (snapshot.isEmpty) {
      throw StateError('Cannot check out an empty cart');
    }
    // The one bill-level discount is shared across the lines *before* their
    // tax is worked out. Storing each row taxed on its full shelf value and
    // deducting the discount only in the bill footer overstated the GST on
    // every discounted sale — the rows are what the reports add up, so the
    // shop would have been remitting tax on money it never took.
    final shares = allocateDiscount([
      for (final line in snapshot) line.total,
    ], _billDiscount.clamp(0, cartGrossTotal).toDouble());
    final interState = _isInterState(customer);
    final taxes = [
      for (var i = 0; i < snapshot.length; i++)
        computeLineTax(
          lineTotal: _money(snapshot[i].total - shares[i]),
          ratePercent: gstRateFor(snapshot[i].product),
          priceIncludesTax: gstSettings.pricesIncludeTax,
          interState: interState,
        ),
    ];

    // Bill-level totals. These and the per-line rows above now come off the
    // same discounted values, so the rows sum to the bill.
    final totals = cartTotals(customer: customer);
    final taxableTotal = totals.taxable;
    final cgst = totals.cgst;
    final sgst = totals.sgst;
    final igst = totals.igst;
    final grandTotal = totals.total;
    final discountTotal = totals.billDiscount + totals.lineDiscount;
    var costTotal = 0.0;
    for (final line in snapshot) {
      costTotal += line.cost;
    }

    // Profit is measured on the taxable value: GST collected belongs to the
    // government, not the shop, so counting it as revenue overstates margin.
    final profit = _money(taxableTotal - costTotal);
    final soldAt = DateTime.now();

    late SaleRecord sale;
    await _db.transaction(() async {
      final receipt = await _nextInvoiceNumber(soldAt);
      final saleId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              customerId: Value(customer?.id),
              userId: currentUser?.id ?? await _adminUserId(),
              receiptNumber: receipt,
              subtotal: Value(taxableTotal),
              discountTotal: Value(_money(discountTotal)),
              taxTotal: Value(_money(cgst + sgst + igst)),
              grandTotal: Value(grandTotal),
              paidAmount: Value(paid),
              paymentMethod: Value(paymentMethod),
              cashAmount: Value(cashAmount),
              cardAmount: Value(cardAmount),
              upiAmount: Value(upiAmount),
              cgstTotal: Value(cgst),
              sgstTotal: Value(sgst),
              igstTotal: Value(igst),
              placeOfSupply: Value(
                customer?.effectiveStateCode ??
                    storeProfile?.effectiveStateCode,
              ),
              shiftId: Value(openShift?.id),
              customerGstin: Value(
                (customer?.gstin.trim().isNotEmpty ?? false)
                    ? customer!.gstin.trim()
                    : null,
              ),
              soldAt: Value(soldAt),
            ),
          );
      for (var i = 0; i < snapshot.length; i++) {
        final line = snapshot[i];
        final tax = taxes[i];
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: line.product.id,
                quantity: line.quantity.toDouble(),
                unitPrice: line.product.sellingPrice,
                discountAmount: Value(_money(line.discount + shares[i])),
                taxAmount: Value(tax.taxAmount),
                lineTotal: gstSettings.pricesIncludeTax
                    ? _money(line.total - shares[i])
                    : tax.grossValue,
                hsnCode: Value(_hsnFor(line.product)),
                taxRate: Value(tax.ratePercent),
                taxableValue: Value(tax.taxableValue),
                costPrice: Value(line.product.purchasePrice),
              ),
            );
        // Read the level inside the transaction rather than trusting the copy
        // the cart line is holding: refresh() replaces every ProductRecord, so
        // a bill that was open while a delivery landed would otherwise write
        // back a figure from before it. Clamped at zero because a rail cannot
        // hold minus seven shirts — an oversell is a counting error to correct,
        // not a negative to carry forward.
        final onHand =
            (await (_db.select(_db.products)
                      ..where((p) => p.id.equals(line.product.id)))
                    .getSingleOrNull())
                ?.currentStock ??
            line.product.stock;
        final after = (onHand - line.quantity)
            .clamp(0, double.infinity)
            .toDouble();
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(line.product.id)))
            .write(ProductsCompanion(currentStock: Value(after)));
        await _db
            .into(_db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                productId: line.product.id,
                movementType: 'sale',
                quantity: -line.quantity.toDouble(),
                referenceType: const Value('sales'),
                referenceId: Value(saleId),
              ),
            );
      }
      if (customer != null && paid < grandTotal) {
        await (_db.update(
          _db.customers,
        )..where((c) => c.id.equals(customer.id))).write(
          CustomersCompanion(
            currentBalance: Value(_money(customer.balance + grandTotal - paid)),
          ),
        );
      }
      await _audit(
        'CREATE',
        'sales',
        saleId,
        'Completed $receipt for ${AppFormatters.currency(grandTotal)}',
      );
      sale = SaleRecord(
        receipt: receipt,
        customerName: customer?.name ?? 'Walk-in',
        total: grandTotal,
        profit: profit,
        createdAt: soldAt,
        taxableValue: taxableTotal,
        cgst: cgst,
        sgst: sgst,
        igst: igst,
        discountTotal: _money(discountTotal),
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        cardAmount: cardAmount,
        upiAmount: upiAmount,
        customerGstin: customer?.gstin,
        placeOfSupply:
            customer?.effectiveStateCode ?? storeProfile?.effectiveStateCode,
      );
    });
    cart.clear();
    _billDiscount = 0;
    await refresh();
    return sale;
  }

  String _hsnFor(ProductRecord product) => product.hsnCode.trim().isNotEmpty
      ? product.hsnCode.trim()
      : gstSettings.defaultHsnCode;

  /// Allocates the next invoice number inside the caller's transaction.
  ///
  /// Rule 46 wants a number that is unique and sequential within the financial
  /// year, so the counter is stored in `Settings`, reset each April, and read
  /// and written inside the sale's own transaction — two tills committing at
  /// once cannot land on the same number.
  /// What the next bill will be numbered, without taking the number.
  ///
  /// The card machine is told the bill number when the amount is pushed at it,
  /// so its slip and the shop's bill quote the same order — but that happens
  /// before the sale is written, and a payment the customer then cancels must
  /// not burn a number out of a sequence the GST rules require to be unbroken.
  /// So this reads the counter and leaves it alone; [_nextInvoiceNumber]
  /// advances it later, inside the sale's own transaction.
  Future<String> peekNextInvoiceNumber({DateTime? at}) async {
    final soldAt = at ?? DateTime.now();
    final startYear = soldAt.month >= 4 ? soldAt.year : soldAt.year - 1;
    final label = '${startYear % 100}${(startYear + 1) % 100}'.padLeft(4, '0');
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(invoiceCounterKey))).getSingleOrNull();
    final stored = row == null
        ? <String, dynamic>{}
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
    final storedLabel = stored['year'] as String?;
    final next = (storedLabel == label ? (stored['seq'] as int? ?? 0) : 0) + 1;
    return _formatInvoiceNumber(label, next);
  }

  String _formatInvoiceNumber(String yearLabel, int sequence) {
    final prefix = storeProfile?.receiptNumberPrefix.trim().isNotEmpty == true
        ? storeProfile!.receiptNumberPrefix.trim()
        : 'INV';
    // Rule 46 caps the invoice number at 16 characters.
    final candidate =
        '$prefix/$yearLabel/${sequence.toString().padLeft(4, '0')}';
    return candidate.length <= 16
        ? candidate
        : candidate.substring(candidate.length - 16);
  }

  Future<String> _nextInvoiceNumber(DateTime soldAt) async {
    // The Indian financial year runs April to March, so anything before April
    // still belongs to the year that started the previous April.
    final startYear = soldAt.month >= 4 ? soldAt.year : soldAt.year - 1;
    final label = '${startYear % 100}${(startYear + 1) % 100}'.padLeft(4, '0');

    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(invoiceCounterKey))).getSingleOrNull();
    final stored = row == null
        ? <String, dynamic>{}
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
    final storedLabel = stored['year'] as String?;
    final next = (storedLabel == label ? (stored['seq'] as int? ?? 0) : 0) + 1;

    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: invoiceCounterKey,
            valueJson: jsonEncode({'year': label, 'seq': next}),
          ),
        );

    return _formatInvoiceNumber(label, next);
  }

  static double _money(double value) => (value * 100).roundToDouble() / 100;

  // ----------------------------------------------------------- purchases

  /// One line of a goods receipt.
  ///
  /// Cost is per piece, so the person receiving a delivery types the number on
  /// the supplier's invoice rather than working out a total.
  Future<int> receiveStock({
    required int supplierId,
    required String invoiceNumber,
    required Map<int, PurchaseLine> lines,
    DateTime? purchasedAt,
    double paidAmount = 0,
    String? invoiceFilePath,
  }) async {
    final entries = lines.entries.where((e) => e.value.quantity > 0).toList();
    if (entries.isEmpty) {
      throw StateError('Enter a quantity for at least one item.');
    }
    if (invoiceNumber.trim().isEmpty) {
      throw StateError("Enter the supplier's invoice number.");
    }

    final clash =
        await (_db.select(_db.purchases)
              ..where((p) => p.invoiceNumber.equals(invoiceNumber.trim())))
            .getSingleOrNull();
    if (clash != null) {
      throw StateError('Invoice ${invoiceNumber.trim()} is already recorded.');
    }

    final at = purchasedAt ?? DateTime.now();
    var subtotal = 0.0;
    for (final entry in entries) {
      subtotal += entry.value.quantity * entry.value.unitCost;
    }
    subtotal = _money(subtotal);

    // Copied before the transaction opens: a file that cannot be read must
    // fail the delivery outright rather than half-way through writing it.
    final storedInvoice = await _copyPurchaseInvoice(
      invoiceFilePath,
      invoiceNumber.trim(),
    );

    late int purchaseId;
    await _db.transaction(() async {
      purchaseId = await _db
          .into(_db.purchases)
          .insert(
            PurchasesCompanion.insert(
              supplierId: supplierId,
              invoiceNumber: invoiceNumber.trim(),
              subtotal: Value(subtotal),
              grandTotal: Value(subtotal),
              paidAmount: Value(_money(paidAmount)),
              invoicePath: Value(storedInvoice),
              purchasedAt: Value(at),
            ),
          );

      for (final entry in entries) {
        final productId = entry.key;
        final line = entry.value;
        await _db
            .into(_db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: purchaseId,
                productId: productId,
                quantity: line.quantity,
                unitCost: line.unitCost,
                lineTotal: _money(line.quantity * line.unitCost),
              ),
            );

        final product = await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(productId))).getSingleOrNull();
        if (product != null) {
          // The cost price follows the latest delivery, so margin is measured
          // against what the shop most recently paid.
          await (_db.update(
            _db.products,
          )..where((p) => p.id.equals(productId))).write(
            ProductsCompanion(
              currentStock: Value(product.currentStock + line.quantity),
              purchasePrice: Value(line.unitCost),
            ),
          );
        }
        await _db
            .into(_db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                productId: productId,
                movementType: 'purchase',
                quantity: line.quantity,
                referenceType: const Value('purchases'),
                referenceId: Value(purchaseId),
              ),
            );
      }

      // Anything unpaid is owed to the supplier.
      final owing = subtotal - _money(paidAmount);
      if (owing != 0) {
        final supplier = await (_db.select(
          _db.suppliers,
        )..where((s) => s.id.equals(supplierId))).getSingleOrNull();
        if (supplier != null) {
          await (_db.update(
            _db.suppliers,
          )..where((s) => s.id.equals(supplierId))).write(
            SuppliersCompanion(
              currentBalance: Value(_money(supplier.currentBalance + owing)),
            ),
          );
        }
      }

      await _audit(
        'CREATE',
        'purchases',
        purchaseId,
        'Received ${entries.length} item(s) on invoice ${invoiceNumber.trim()} '
            'for ${AppFormatters.currency(subtotal)}',
      );
    });

    await refresh();
    return purchaseId;
  }

  /// Which file types a delivery's proof may be. A wholesaler either emails a
  /// PDF or the shop photographs the paper, and both have to be accepted.
  static const purchaseInvoiceExtensions = <String>[
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
  ];

  /// Copies the supplier's invoice into the app's own folder and returns the
  /// stored path.
  ///
  /// Our own copy on purpose: the original is usually in Downloads or on a
  /// phone's memory card, and a proof of purchase that disappears when someone
  /// tidies their desktop is not a proof of anything. It also means the backup
  /// zip carries it, since that walks this folder.
  Future<String?> _copyPurchaseInvoice(
    String? sourcePath,
    String invoice,
  ) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath.trim());
    if (!source.existsSync()) {
      throw StateError('That invoice file could not be found.');
    }
    final extension = p
        .extension(source.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!purchaseInvoiceExtensions.contains(extension)) {
      throw StateError(
        'Attach the invoice as a PDF or an image '
        '(${purchaseInvoiceExtensions.join(', ')}).',
      );
    }

    final directory = await _appDataDirectory();
    final folder = Directory(p.join(directory.path, 'purchase_invoices'));
    if (!folder.existsSync()) folder.createSync(recursive: true);

    // The invoice number goes in the filename so the folder can be read by a
    // human, with anything a file system dislikes stripped out.
    final safe = invoice.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final target = File(
      p.join(
        folder.path,
        '$safe-${DateTime.now().millisecondsSinceEpoch}.$extension',
      ),
    );
    await source.copy(target.path);
    return target.path;
  }

  /// Attaches, replaces or clears the scanned invoice on a delivery already
  /// recorded — the usual case being that the paper turned up after the stock.
  Future<void> setPurchaseInvoiceFile(
    int purchaseId,
    String? sourcePath,
  ) async {
    final row = await (_db.select(
      _db.purchases,
    )..where((p) => p.id.equals(purchaseId))).getSingleOrNull();
    if (row == null) {
      throw StateError('That delivery could not be found.');
    }
    final stored = await _copyPurchaseInvoice(sourcePath, row.invoiceNumber);

    // The old copy goes only once the new one is safely written.
    final previous = row.invoicePath;
    await (_db.update(_db.purchases)..where((p) => p.id.equals(purchaseId)))
        .write(PurchasesCompanion(invoicePath: Value(stored)));
    if (previous != null && previous != stored) {
      try {
        final file = File(previous);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // An orphaned copy costs a few kilobytes; failing here would cost the
        // attachment.
      }
    }
    await _audit(
      'UPDATE',
      'purchases',
      purchaseId,
      stored == null
          ? 'Removed the invoice file from ${row.invoiceNumber}'
          : 'Attached an invoice file to ${row.invoiceNumber}',
    );
    await refresh();
  }

  final purchases = <PurchaseRecord>[];

  Future<void> _loadPurchases() async {
    final supplierNames = {
      for (final s in await _db.select(_db.suppliers).get()) s.id: s.name,
    };
    final counts = <int, int>{};
    for (final item in await _db.select(_db.purchaseItems).get()) {
      counts.update(item.purchaseId, (v) => v + 1, ifAbsent: () => 1);
    }
    final rows = await (_db.select(
      _db.purchases,
    )..orderBy([(p) => OrderingTerm.desc(p.purchasedAt)])).get();

    purchases
      ..clear()
      ..addAll(
        rows.map(
          (r) => PurchaseRecord(
            id: r.id,
            invoiceNumber: r.invoiceNumber,
            supplierId: r.supplierId,
            supplierName: supplierNames[r.supplierId] ?? 'Unknown',
            total: r.grandTotal,
            paid: r.paidAmount,
            settled: r.settledAmount,
            invoicePath: r.invoicePath,
            purchasedAt: r.purchasedAt,
            lineCount: counts[r.id] ?? 0,
          ),
        ),
      );
  }

  // ------------------------------------------------------------ expenses

  /// Records what the shop spent, so net profit is not just gross margin.
  Future<int> saveExpense({
    required String category,
    required String title,
    required double amount,
    String? notes,
    DateTime? spentAt,
  }) async {
    if (title.trim().isEmpty) throw StateError('Enter what it was for.');
    if (amount <= 0) throw StateError('Enter an amount above zero.');

    final categoryId = await _ensureExpenseCategory(category);
    final id = await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            categoryId: categoryId,
            title: title.trim(),
            amount: _money(amount),
            notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
            spentAt: Value(spentAt ?? DateTime.now()),
          ),
        );
    await _audit(
      'CREATE',
      'expenses',
      id,
      'Spent ${AppFormatters.currency(amount)} on ${title.trim()}',
    );
    await refresh();
    return id;
  }

  Future<int> _ensureExpenseCategory(String name) async {
    final normalized = name.trim().isEmpty ? 'General' : name.trim();
    final existing = await (_db.select(
      _db.expenseCategories,
    )..where((c) => c.name.equals(normalized))).getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.expenseCategories)
        .insert(ExpenseCategoriesCompanion.insert(name: normalized));
  }

  Future<void> deleteExpense(int id) async {
    await (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();
    await _audit('DELETE', 'expenses', id, 'Removed an expense');
    await refresh();
  }

  final expenses = <ExpenseRecord>[];
  final expenseCategoryNames = <String>[];

  Future<void> _loadExpenses() async {
    final categories = {
      for (final c in await _db.select(_db.expenseCategories).get())
        c.id: c.name,
    };
    expenseCategoryNames
      ..clear()
      ..addAll(categories.values);

    final rows = await (_db.select(
      _db.expenses,
    )..orderBy([(e) => OrderingTerm.desc(e.spentAt)])).get();

    expenses
      ..clear()
      ..addAll(
        rows.map(
          (r) => ExpenseRecord(
            id: r.id,
            category: categories[r.categoryId] ?? 'General',
            title: r.title,
            amount: r.amount,
            notes: r.notes,
            spentAt: r.spentAt,
          ),
        ),
      );
  }

  /// Everything spent inside a window, for the profit-and-loss line.
  double expensesBetween(DateTime from, DateTime to) => expenses
      .where((e) => !e.spentAt.isBefore(from) && e.spentAt.isBefore(to))
      .fold(0.0, (sum, e) => sum + e.amount);

  // ------------------------------------------------------------- held bills

  final heldBills = <HeldBillRecord>[];

  /// Parks the current basket so the counter can serve someone else.
  ///
  /// The customer has gone to try something on; the next person is waiting.
  /// Everything about the basket is written to disk, because the shop's power
  /// is not reliable and a crash must not cost a full trolley.
  Future<HeldBillRecord> holdCurrentBill({
    required String label,
    CustomerRecord? customer,
  }) async {
    if (cart.isEmpty) {
      throw StateError('There is nothing on the bill to hold.');
    }
    final name = label.trim().isEmpty
        ? 'Held at ${AppFormatters.dateTime(DateTime.now())}'
        : label.trim();

    final snapshot = List<CartLine>.from(cart);
    late int id;
    await _db.transaction(() async {
      id = await _db
          .into(_db.heldBills)
          .insert(
            HeldBillsCompanion.insert(
              label: name,
              customerId: Value(customer?.id),
              userId: Value(currentUser?.id),
            ),
          );
      for (final line in snapshot) {
        await _db
            .into(_db.heldBillItems)
            .insert(
              HeldBillItemsCompanion.insert(
                heldBillId: id,
                productId: line.product.id,
                quantity: line.quantity,
                discount: Value(line.discount),
              ),
            );
      }
    });

    cart.clear();
    await _audit('CREATE', 'held_bills', id, 'Held a bill as "$name"');
    await refresh();
    return heldBills.firstWhere((b) => b.id == id);
  }

  /// Puts a held bill back on the counter and removes it from the held list.
  ///
  /// Anything already in the cart is kept — recalling adds to it rather than
  /// throwing away what the assistant has just scanned.
  Future<void> recallHeldBill(int id) async {
    final held = heldBills.where((b) => b.id == id).firstOrNull;
    if (held == null) throw StateError('That held bill is no longer there.');

    for (final line in held.lines) {
      final product = products.where((p) => p.id == line.productId).firstOrNull;
      // A product deleted while the bill was parked is skipped rather than
      // taking the whole recall down.
      if (product == null) continue;
      final existing = cart
          .where((c) => c.product.id == product.id)
          .firstOrNull;
      if (existing == null) {
        cart.add(
          CartLine(
            product: product,
            quantity: line.quantity,
            discount: line.discount,
          ),
        );
      } else {
        existing.quantity += line.quantity;
        existing.discount += line.discount;
      }
    }

    await (_db.delete(_db.heldBills)..where((b) => b.id.equals(id))).go();
    await _audit('DELETE', 'held_bills', id, 'Recalled "${held.label}"');
    await refresh();
  }

  /// Throws a held bill away without selling it.
  Future<void> discardHeldBill(int id) async {
    final held = heldBills.where((b) => b.id == id).firstOrNull;
    await (_db.delete(_db.heldBills)..where((b) => b.id.equals(id))).go();
    await _audit(
      'DELETE',
      'held_bills',
      id,
      'Discarded "${held?.label ?? id}"',
    );
    await refresh();
  }

  Future<void> _loadHeldBills() async {
    final rows = await (_db.select(
      _db.heldBills,
    )..orderBy([(b) => OrderingTerm.desc(b.heldAt)])).get();
    final items = await _db.select(_db.heldBillItems).get();
    final byProduct = {for (final p in products) p.id: p};
    final customerNames = {for (final c in customers) c.id: c.name};

    heldBills
      ..clear()
      ..addAll(
        rows.map((row) {
          final lines = items
              .where((i) => i.heldBillId == row.id)
              .map(
                (i) => HeldBillLine(
                  productId: i.productId,
                  description:
                      byProduct[i.productId]?.displayName ?? 'Removed product',
                  quantity: i.quantity,
                  discount: i.discount,
                  unitPrice: byProduct[i.productId]?.sellingPrice ?? 0,
                ),
              )
              .toList();
          return HeldBillRecord(
            id: row.id,
            label: row.label,
            customerName: customerNames[row.customerId],
            heldAt: row.heldAt,
            lines: lines,
          );
        }),
      );
  }

  // ------------------------------------------------ stock adjustments

  /// Corrects what the books say is on the rail — damage, a sample taken, a
  /// miscount spotted while tidying, or a recount of one peg.
  ///
  /// This is the whole of stock correction now: the separate stock-count
  /// screen is gone, because a shop that adjusts one design at a time from the
  /// catalogue never needed a session to do it in.
  ///
  /// [delta] is the change, not the new level: -2 for two shirts written off.
  Future<void> adjustStock({
    required int productId,
    required double delta,
    required String reason,
  }) async {
    if (delta == 0) {
      throw StateError('Enter how many to add or take off.');
    }
    if (reason.trim().isEmpty) {
      throw StateError('Say why the stock is being adjusted.');
    }
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      throw StateError('That product could not be found.');
    }
    final after = product.stock + delta;
    if (after < 0) {
      throw StateError(
        'That would leave ${product.displayName} below zero. There are '
        '${AppFormatters.quantity(product.stock)} on the books.',
      );
    }

    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(currentStock: Value(after)));
      await _db
          .into(_db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              productId: productId,
              movementType: 'adjustment',
              quantity: delta,
              referenceType: const Value('adjustments'),
            ),
          );
      await _audit(
        'UPDATE',
        'products',
        productId,
        'Adjusted ${product.displayName} by '
            '${delta > 0 ? '+' : ''}${AppFormatters.quantity(delta)}: '
            '${reason.trim()}',
      );
    });
    await refresh();
  }

  // ------------------------------------------------- payments & statements

  final partyPayments = <PartyPaymentRecord>[];

  /// Records money settled against a party's balance and moves that balance.
  ///
  /// A credit sale grows what a customer owes and an unpaid delivery grows what
  /// the shop owes its supplier; this is the only thing that brings either back
  /// down. Cash settled while a till session is open also posts a cash movement
  /// so the drawer still reconciles at close — otherwise the money would be in
  /// the till at close with nothing explaining it.
  Future<PartyPaymentRecord> recordPartyPayment({
    required PartyKind kind,
    required int partyId,
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    String notes = '',
    DateTime? paidAt,
  }) async {
    final rounded = _money(amount);
    if (rounded <= 0) {
      throw StateError('Enter an amount greater than zero.');
    }

    final name = kind == PartyKind.customer
        ? customers.where((c) => c.id == partyId).firstOrNull?.name
        : suppliers.where((s) => s.id == partyId).firstOrNull?.name;
    if (name == null) {
      throw StateError('That ${kind.name} could not be found.');
    }

    final when = paidAt ?? DateTime.now();
    late PartyPaymentRecord record;
    await _db.transaction(() async {
      final reference = await _nextPaymentReference(kind, when);
      final id = await _db
          .into(_db.partyPayments)
          .insert(
            PartyPaymentsCompanion.insert(
              partyType: kind.name,
              partyId: partyId,
              reference: reference,
              amount: rounded,
              method: Value(method.name),
              notes: Value(notes.trim().isEmpty ? null : notes.trim()),
              userId: Value(currentUser?.id),
              paidAt: Value(when),
            ),
          );

      if (kind == PartyKind.customer) {
        final customer = customers.firstWhere((c) => c.id == partyId);
        await (_db.update(
          _db.customers,
        )..where((c) => c.id.equals(partyId))).write(
          CustomersCompanion(
            currentBalance: Value(_money(customer.balance - rounded)),
          ),
        );
      } else {
        final supplier = suppliers.firstWhere((s) => s.id == partyId);
        await (_db.update(
          _db.suppliers,
        )..where((s) => s.id.equals(partyId))).write(
          SuppliersCompanion(
            currentBalance: Value(_money(supplier.balance - rounded)),
          ),
        );
        // Spread the payment over the deliveries it settles, oldest first,
        // which is how a wholesaler applies money against an account. It goes
        // into settledAmount rather than paidAmount so the statement can still
        // tell "owed on the day" apart from "paid since" — putting both in one
        // column would net the payment off the delivery *and* show it as a
        // credit, counting it twice.
        var remaining = rounded;
        final duePurchases =
            await (_db.select(_db.purchases)
                  ..where((p) => p.supplierId.equals(partyId))
                  ..orderBy([(p) => OrderingTerm.asc(p.purchasedAt)]))
                .get();
        for (final purchase in duePurchases) {
          if (remaining <= 0) break;
          final outstanding = _money(
            purchase.grandTotal - purchase.paidAmount - purchase.settledAmount,
          );
          if (outstanding <= 0) continue;
          final applied = remaining > outstanding ? outstanding : remaining;
          await (_db.update(
            _db.purchases,
          )..where((p) => p.id.equals(purchase.id))).write(
            PurchasesCompanion(
              settledAmount: Value(_money(purchase.settledAmount + applied)),
            ),
          );
          remaining = _money(remaining - applied);
        }
      }

      await _audit(
        'CREATE',
        'party_payments',
        id,
        '${kind == PartyKind.customer ? 'Received from' : 'Paid'} $name: '
            '${AppFormatters.currency(rounded)} ($reference)',
      );

      record = PartyPaymentRecord(
        id: id,
        kind: kind,
        partyId: partyId,
        partyName: name,
        reference: reference,
        amount: rounded,
        method: method,
        paidAt: when,
        notes: notes.trim(),
        userName: currentUser?.name ?? '',
      );
    });

    // Cash across the counter belongs to the open drawer, in either direction.
    if (method == PaymentMethod.cash && openShift != null) {
      await recordCashMovement(
        amount: rounded,
        isIn: kind == PartyKind.customer,
        reason: kind == PartyKind.customer
            ? 'Received from $name (${record.reference})'
            : 'Paid to $name (${record.reference})',
      );
    }

    await refresh();
    return record;
  }

  /// Voucher numbers run RCP/… for money in and PMT/… for money out, sequential
  /// within the financial year so a shop can quote one over the phone.
  Future<String> _nextPaymentReference(PartyKind kind, DateTime at) async {
    final startYear = at.month >= 4 ? at.year : at.year - 1;
    final label = '${startYear % 100}${(startYear + 1) % 100}'.padLeft(4, '0');
    final prefix = kind == PartyKind.customer ? 'RCP' : 'PMT';

    final existing = await (_db.select(
      _db.partyPayments,
    )..where((p) => p.reference.like('$prefix/$label/%'))).get();
    var highest = 0;
    for (final row in existing) {
      final tail = int.tryParse(row.reference.split('/').last) ?? 0;
      if (tail > highest) highest = tail;
    }
    return '$prefix/$label/${(highest + 1).toString().padLeft(4, '0')}';
  }

  Future<void> _loadPartyPayments() async {
    final rows = await (_db.select(
      _db.partyPayments,
    )..orderBy([(p) => OrderingTerm.desc(p.paidAt)])).get();
    final names = {
      for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
    };

    partyPayments
      ..clear()
      ..addAll(
        rows.map((r) {
          final kind = r.partyType == PartyKind.supplier.name
              ? PartyKind.supplier
              : PartyKind.customer;
          final party = kind == PartyKind.customer
              ? customers.where((c) => c.id == r.partyId).firstOrNull?.name
              : suppliers.where((s) => s.id == r.partyId).firstOrNull?.name;
          return PartyPaymentRecord(
            id: r.id,
            kind: kind,
            partyId: r.partyId,
            partyName: party ?? 'Unknown',
            reference: r.reference,
            amount: r.amount,
            method: PaymentMethod.fromName(r.method),
            paidAt: r.paidAt,
            notes: r.notes ?? '',
            userName: names[r.userId] ?? '',
          );
        }),
      );
  }

  /// Builds a statement of account for one party over [range].
  ///
  /// The opening balance is worked backwards from where the party stands today,
  /// undoing every movement from the end of the window onwards. Doing it that
  /// way means the closing figure always agrees with the balance shown on the
  /// customers screen, which is the number anyone will check it against.
  /// How a bill was paid, in words a customer reads on their statement.
  static String _methodLabel(String method) => switch (method) {
    'cash' => 'cash',
    'card' => 'card',
    'upi' => 'UPI',
    'split' => 'split tender',
    _ => method,
  };

  Future<StatementBundle> buildStatement({
    required PartyKind kind,
    required int partyId,
    required DateRange range,
  }) async {
    final movements = <StatementMovement>[];
    var balanceNow = 0.0;
    var name = 'Unknown', phone = '', address = '', gstin = '';

    if (kind == PartyKind.customer) {
      final customer = customers.where((c) => c.id == partyId).firstOrNull;
      if (customer == null) {
        throw StateError('That customer could not be found.');
      }
      name = customer.name;
      phone = customer.phone;
      address = customer.address;
      gstin = customer.gstin;
      balanceNow = customer.balance;

      // Every bill this customer bought, not just the ones left unpaid.
      //
      // This used to skip any sale where grandTotal == paidAmount, so a
      // customer who always pays cash had a completely empty statement — the
      // one thing they came to the counter to see. A statement is a purchase
      // history first and a debt ledger second, so the bill goes on as a
      // debit for what was charged and the money taken at the till goes on as
      // a credit. The running balance is unchanged: debit less credit is
      // still exactly what is outstanding on that bill.
      final sales =
          await (_db.select(_db.sales)
                ..where((s) => s.customerId.equals(partyId))
                ..orderBy([(s) => OrderingTerm.asc(s.soldAt)]))
              .get();
      for (final sale in sales) {
        final paid = _money(sale.paidAmount);
        final billed = _money(sale.grandTotal);
        movements.add(
          StatementMovement(
            date: sale.soldAt,
            reference: sale.receiptNumber,
            description: paid >= billed
                ? 'Sale (${_methodLabel(sale.paymentMethod)})'
                : paid <= 0
                ? 'Sale on credit'
                : 'Sale, part paid (${_methodLabel(sale.paymentMethod)})',
            debit: billed,
          ),
        );
        if (paid > 0) {
          movements.add(
            StatementMovement(
              date: sale.soldAt,
              reference: sale.receiptNumber,
              description: 'Paid at the till',
              credit: paid,
            ),
          );
        }
      }

      final credits = await (_db.select(
        _db.returns,
      )..where((r) => r.customerId.equals(partyId))).get();
      for (final credit in credits) {
        if (credit.refundMethod != 'credit') continue;
        movements.add(
          StatementMovement(
            date: credit.returnedAt,
            reference: credit.returnNumber,
            description: 'Credit note',
            credit: credit.totalAmount,
          ),
        );
      }
    } else {
      final supplier = suppliers.where((s) => s.id == partyId).firstOrNull;
      if (supplier == null) {
        throw StateError('That supplier could not be found.');
      }
      name = supplier.name;
      phone = supplier.phone;
      address = supplier.address;
      balanceNow = supplier.balance;

      final deliveries = await (_db.select(
        _db.purchases,
      )..where((p) => p.supplierId.equals(partyId))).get();
      for (final delivery in deliveries) {
        final unpaid = _money(delivery.grandTotal - delivery.paidAmount);
        if (unpaid <= 0) continue;
        movements.add(
          StatementMovement(
            date: delivery.purchasedAt,
            reference: delivery.invoiceNumber,
            description: 'Delivery received',
            debit: unpaid,
          ),
        );
      }
    }

    for (final payment in partyPayments) {
      if (payment.kind != kind || payment.partyId != partyId) continue;
      movements.add(
        StatementMovement(
          date: payment.paidAt,
          reference: payment.reference,
          description: kind == PartyKind.customer
              ? 'Payment received (${payment.method.label})'
              : 'Payment made (${payment.method.label})',
          credit: payment.amount,
        ),
      );
    }

    // Everything after the window has to be undone to find where the balance
    // stood when it closed, and everything inside it to find the opening.
    final after = movements.where((m) => !m.date.isBefore(range.to));
    final inside = movements.where(
      (m) => !m.date.isBefore(range.from) && m.date.isBefore(range.to),
    );
    final closing =
        balanceNow - after.fold(0.0, (sum, m) => sum + m.debit - m.credit);
    final opening =
        closing - inside.fold(0.0, (sum, m) => sum + m.debit - m.credit);

    return StatementBundle(
      kind: kind,
      partyId: partyId,
      partyName: name,
      range: range,
      openingBalance: _money(opening),
      lines: runningBalance(_money(opening), inside.toList()),
      phone: phone,
      address: address,
      gstin: gstin,
    );
  }

  // ------------------------------------------------------------- reports

  /// Builds every report for [range] in one pass over the data.
  ///
  /// Everything is derived from sale *lines* rather than bill headers, because
  /// a GST return needs tax broken down by rate and by HSN, and neither is
  /// recoverable from a total.
  Future<ReportBundle> buildReports(DateRange range) async {
    final saleRows =
        await (_db.select(_db.sales)
              ..where(
                (s) =>
                    s.soldAt.isBiggerOrEqualValue(range.from) &
                    s.soldAt.isSmallerThanValue(range.to),
              )
              ..orderBy([(s) => OrderingTerm.desc(s.soldAt)]))
            .get();
    final saleIds = saleRows.map((s) => s.id).toList();

    final items = saleIds.isEmpty
        ? <SaleItemRow>[]
        : await (_db.select(
            _db.saleItems,
          )..where((i) => i.saleId.isIn(saleIds))).get();

    final customerNames = {
      for (final c in await _db.select(_db.customers).get()) c.id: c.name,
    };
    final userNames = {
      for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
    };
    final productRows = await _db.select(_db.products).get();
    final products = {for (final p in productRows) p.id: p};

    // Profit per bill, from the cost captured at the time of sale.
    final profitBySale = <int, double>{};
    for (final item in items) {
      final lineProfit = item.taxableValue - item.costPrice * item.quantity;
      profitBySale.update(
        item.saleId,
        (v) => v + lineProfit,
        ifAbsent: () => lineProfit,
      );
    }

    final register = [
      for (final sale in saleRows)
        RegisterRow(
          receiptNumber: sale.receiptNumber,
          soldAt: sale.soldAt,
          customerName: customerNames[sale.customerId] ?? 'Walk-in',
          customerGstin: sale.customerGstin,
          taxableValue: sale.subtotal,
          cgst: sale.cgstTotal,
          sgst: sale.sgstTotal,
          igst: sale.igstTotal,
          discount: sale.discountTotal,
          grandTotal: sale.grandTotal,
          profit: _money(profitBySale[sale.id] ?? 0),
          paymentMethod: sale.paymentMethod,
          cashAmount: sale.cashAmount,
          cardAmount: sale.cardAmount,
          upiAmount: sale.upiAmount,
          soldBy: userNames[sale.userId] ?? '—',
        ),
    ];

    // Which bills were inter-state, so line tax lands in the right column.
    final interState = {
      for (final sale in saleRows) sale.id: sale.igstTotal > 0,
    };

    final byRate = <double, _RateBucket>{};
    final byHsn = <String, _HsnBucket>{};
    final byProduct = <int, _ProductBucket>{};

    for (final item in items) {
      final isIgst = interState[item.saleId] ?? false;
      final rate = item.taxRate;

      byRate
          .putIfAbsent(rate, () => _RateBucket())
          .add(item.taxableValue, item.taxAmount, isIgst);

      final hsn = (item.hsnCode ?? '').isEmpty ? '—' : item.hsnCode!;
      final product = products[item.productId];
      byHsn
          .putIfAbsent(hsn, () => _HsnBucket(product?.name ?? 'Item'))
          .add(item.quantity, item.taxableValue, item.taxAmount);

      byProduct
          .putIfAbsent(
            item.productId,
            () => _ProductBucket(
              product == null
                  ? 'Item ${item.productId}'
                  : _variantLabel(product),
              product?.currentStock ?? 0,
            ),
          )
          .add(
            item.quantity,
            item.lineTotal,
            item.taxableValue - item.costPrice * item.quantity,
          );
    }

    final gstByRate =
        byRate.entries
            .map(
              (e) => GstRateSummary(
                ratePercent: e.key,
                taxableValue: _money(e.value.taxable),
                cgst: _money(e.value.cgst),
                sgst: _money(e.value.sgst),
                igst: _money(e.value.igst),
                lineCount: e.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => a.ratePercent.compareTo(b.ratePercent));

    final hsnSummary =
        byHsn.entries
            .map(
              (e) => HsnSummary(
                hsnCode: e.key,
                description: e.value.description,
                quantity: e.value.quantity,
                taxableValue: _money(e.value.taxable),
                taxAmount: _money(e.value.tax),
                total: _money(e.value.taxable + e.value.tax),
              ),
            )
            .toList()
          ..sort((a, b) => b.taxableValue.compareTo(a.taxableValue));

    final sold =
        byProduct.entries
            .map(
              (e) => ProductPerformance(
                productId: e.key,
                description: e.value.description,
                quantitySold: e.value.quantity,
                revenue: _money(e.value.revenue),
                profit: _money(e.value.profit),
                stockOnHand: e.value.stockOnHand,
              ),
            )
            .toList()
          ..sort((a, b) => b.quantitySold.compareTo(a.quantitySold));

    // Anything on the shelf that did not move in the window.
    final soldIds = byProduct.keys.toSet();
    final deadStock =
        productRows
            .where(
              (p) =>
                  p.isActive && p.currentStock > 0 && !soldIds.contains(p.id),
            )
            .map(
              (p) => ProductPerformance(
                productId: p.id,
                description: _variantLabel(p),
                quantitySold: 0,
                revenue: 0,
                profit: 0,
                stockOnHand: p.currentStock,
              ),
            )
            .toList()
          ..sort((a, b) => (b.stockOnHand).compareTo(a.stockOnHand));

    final returnRows =
        await (_db.select(_db.returns)..where(
              (r) =>
                  r.returnedAt.isBiggerOrEqualValue(range.from) &
                  r.returnedAt.isSmallerThanValue(range.to),
            ))
            .get();

    return ReportBundle(
      range: range,
      register: register,
      gstByRate: gstByRate,
      hsn: hsnSummary,
      topSellers: sold,
      deadStock: deadStock,
      returnsTotal: _money(
        returnRows.fold(0.0, (sum, r) => sum + r.totalAmount),
      ),
      returnsTax: _money(
        returnRows.fold(
          0.0,
          (sum, r) => sum + r.cgstTotal + r.sgstTotal + r.igstTotal,
        ),
      ),
      returnCount: returnRows.length,
    );
  }

  static String _variantLabel(ProductRow product) {
    final variant = [
      product.color ?? '',
      product.size ?? '',
    ].where((v) => v.isNotEmpty).join(' / ');
    return variant.isEmpty ? product.name : '${product.name} ($variant)';
  }

  // ------------------------------------------------------------- returns

  /// Finds a bill by its number so it can be returned against.
  ///
  /// Quantities already refunded on earlier returns are subtracted, so the
  /// same garment cannot be refunded twice.
  Future<ReturnableSale?> findSaleByReceipt(String receiptNumber) async {
    final query = receiptNumber.trim();
    if (query.isEmpty) return null;

    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.receiptNumber.equals(query))).getSingleOrNull();
    if (sale == null) return null;

    final items = await (_db.select(
      _db.saleItems,
    )..where((i) => i.saleId.equals(sale.id))).get();

    // Everything already returned against this bill, per sale line.
    final returnedByProduct = <int, double>{};
    final priorReturns = await (_db.select(
      _db.returns,
    )..where((r) => r.saleId.equals(sale.id))).get();
    if (priorReturns.isNotEmpty) {
      final ids = priorReturns.map((r) => r.id).toList();
      final priorItems = await (_db.select(
        _db.returnItems,
      )..where((i) => i.returnId.isIn(ids))).get();
      for (final item in priorItems) {
        returnedByProduct.update(
          item.productId,
          (v) => v + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }

    final products = {
      for (final p in await _db.select(_db.products).get()) p.id: p,
    };
    final customer = sale.customerId == null
        ? null
        : await (_db.select(
            _db.customers,
          )..where((c) => c.id.equals(sale.customerId!))).getSingleOrNull();

    return ReturnableSale(
      saleId: sale.id,
      receiptNumber: sale.receiptNumber,
      soldAt: sale.soldAt,
      customerId: sale.customerId,
      customerName: customer?.name ?? 'Walk-in',
      grandTotal: sale.grandTotal,
      isInterState: sale.igstTotal > 0,
      lines: [
        for (final item in items)
          () {
            final product = products[item.productId];
            final label = product == null
                ? 'Item ${item.productId}'
                : [
                    product.name,
                    if ((product.color ?? '').isNotEmpty ||
                        (product.size ?? '').isNotEmpty)
                      '(${[product.color ?? '', product.size ?? ''].where((v) => v.isNotEmpty).join(' / ')})',
                  ].join(' ');
            return ReturnableLine(
              saleItemId: item.id,
              productId: item.productId,
              description: label,
              hsnCode: item.hsnCode ?? '',
              soldQuantity: item.quantity,
              alreadyReturned: returnedByProduct[item.productId] ?? 0,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
              taxRate: item.taxRate,
              taxableValue: item.taxableValue,
              taxAmount: item.taxAmount,
              costPrice: item.costPrice,
            );
          }(),
      ],
    );
  }

  /// Takes goods back: restocks them, reverses the tax, and either refunds the
  /// money or credits the customer's account.
  ///
  /// Returns the credit note, or throws [StateError] if nothing was selected.
  Future<ReturnRecord> processReturn({
    required ReturnableSale sale,
    required List<ReturnSelection> selections,
    required RefundMethod refundMethod,
    String? reason,
  }) async {
    final chosen = selections.where((s) => s.quantity > 0).toList();
    if (chosen.isEmpty) {
      throw StateError('Choose at least one item to take back.');
    }
    for (final selection in chosen) {
      if (selection.quantity > selection.line.returnableQuantity + 0.001) {
        throw StateError(
          'Cannot take back more ${selection.line.description} than was sold.',
        );
      }
    }

    var refundTotal = 0.0, taxable = 0.0, tax = 0.0;
    for (final selection in chosen) {
      final line = selection.line;
      final refund = line.refundFor(selection.quantity);
      refundTotal += refund;
      // Tax comes back in the same proportion as the goods.
      final share = line.soldQuantity == 0
          ? 0.0
          : selection.quantity / line.soldQuantity;
      taxable += line.taxableValue * share;
      tax += line.taxAmount * share;
    }
    refundTotal = _money(refundTotal);
    taxable = _money(taxable);
    tax = _money(tax);

    final cgst = sale.isInterState ? 0.0 : _money(tax / 2);
    final sgst = sale.isInterState ? 0.0 : _money(tax / 2);
    final igst = sale.isInterState ? tax : 0.0;
    final returnedAt = DateTime.now();

    late ReturnRecord record;
    await _db.transaction(() async {
      final number = await _nextReturnNumber(returnedAt);
      final returnId = await _db
          .into(_db.returns)
          .insert(
            ReturnsCompanion.insert(
              saleId: Value(sale.saleId),
              returnNumber: number,
              totalAmount: Value(refundTotal),
              reason: Value(
                reason?.trim().isEmpty ?? true ? null : reason!.trim(),
              ),
              userId: Value(currentUser?.id),
              customerId: Value(sale.customerId),
              refundMethod: Value(refundMethod.code),
              taxableTotal: Value(taxable),
              cgstTotal: Value(cgst),
              sgstTotal: Value(sgst),
              igstTotal: Value(igst),
              returnedAt: Value(returnedAt),
            ),
          );

      for (final selection in chosen) {
        final line = selection.line;
        final share = line.soldQuantity == 0
            ? 0.0
            : selection.quantity / line.soldQuantity;
        await _db
            .into(_db.returnItems)
            .insert(
              ReturnItemsCompanion.insert(
                returnId: returnId,
                productId: line.productId,
                quantity: selection.quantity,
                refundAmount: _money(line.refundFor(selection.quantity)),
                unitPrice: Value(line.unitPrice),
                taxRate: Value(line.taxRate),
                taxableValue: Value(_money(line.taxableValue * share)),
                taxAmount: Value(_money(line.taxAmount * share)),
                costPrice: Value(line.costPrice),
                hsnCode: Value(line.hsnCode.isEmpty ? null : line.hsnCode),
              ),
            );

        // Goods come back onto the shelf.
        final product = await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(line.productId))).getSingleOrNull();
        if (product != null) {
          await (_db.update(
            _db.products,
          )..where((p) => p.id.equals(line.productId))).write(
            ProductsCompanion(
              currentStock: Value(product.currentStock + selection.quantity),
            ),
          );
        }
        await _db
            .into(_db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                productId: line.productId,
                movementType: 'return',
                quantity: selection.quantity,
                referenceType: const Value('returns'),
                referenceId: Value(returnId),
              ),
            );
      }

      // A credit refund reduces what the customer owes rather than opening the
      // drawer.
      if (refundMethod == RefundMethod.credit && sale.customerId != null) {
        final customer = await (_db.select(
          _db.customers,
        )..where((c) => c.id.equals(sale.customerId!))).getSingleOrNull();
        if (customer != null) {
          await (_db.update(
            _db.customers,
          )..where((c) => c.id.equals(sale.customerId!))).write(
            CustomersCompanion(
              currentBalance: Value(
                _money(customer.currentBalance - refundTotal),
              ),
            ),
          );
        }
      }

      await _audit(
        'CREATE',
        'returns',
        returnId,
        'Return $number against ${sale.receiptNumber} for '
            '${AppFormatters.currency(refundTotal)}',
      );

      record = ReturnRecord(
        id: returnId,
        returnNumber: number,
        saleReceipt: sale.receiptNumber,
        customerName: sale.customerName,
        totalAmount: refundTotal,
        taxableTotal: taxable,
        cgst: cgst,
        sgst: sgst,
        igst: igst,
        refundMethod: refundMethod,
        returnedAt: returnedAt,
        reason: reason,
        lineCount: chosen.length,
      );
    });

    await refresh();
    return record;
  }

  /// Credit-note numbers follow the same gapless-per-financial-year rule as
  /// invoices, in their own sequence.
  Future<String> _nextReturnNumber(DateTime at) async {
    final startYear = at.month >= 4 ? at.year : at.year - 1;
    final label = '${startYear % 100}${(startYear + 1) % 100}'.padLeft(4, '0');
    const key = 'credit_note_counter';

    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final stored = row == null
        ? <String, dynamic>{}
        : jsonDecode(row.valueJson) as Map<String, dynamic>;
    final next =
        (stored['year'] == label ? (stored['seq'] as int? ?? 0) : 0) + 1;

    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            valueJson: jsonEncode({'year': label, 'seq': next}),
          ),
        );
    return 'CN/$label/${next.toString().padLeft(4, '0')}';
  }

  final returns = <ReturnRecord>[];

  Future<void> _loadReturns() async {
    final customerNames = {
      for (final c in await _db.select(_db.customers).get()) c.id: c.name,
    };
    final receipts = {
      for (final s in await _db.select(_db.sales).get()) s.id: s.receiptNumber,
    };
    final counts = <int, int>{};
    for (final item in await _db.select(_db.returnItems).get()) {
      counts.update(item.returnId, (v) => v + 1, ifAbsent: () => 1);
    }
    final rows = await (_db.select(
      _db.returns,
    )..orderBy([(r) => OrderingTerm.desc(r.returnedAt)])).get();

    returns
      ..clear()
      ..addAll(
        rows.map(
          (r) => ReturnRecord(
            id: r.id,
            returnNumber: r.returnNumber,
            saleReceipt: receipts[r.saleId] ?? '—',
            customerName: customerNames[r.customerId] ?? 'Walk-in',
            totalAmount: r.totalAmount,
            taxableTotal: r.taxableTotal,
            cgst: r.cgstTotal,
            sgst: r.sgstTotal,
            igst: r.igstTotal,
            refundMethod: RefundMethod.fromCode(r.refundMethod),
            returnedAt: r.returnedAt,
            reason: r.reason,
            lineCount: counts[r.id] ?? 0,
          ),
        ),
      );
  }

  // -------------------------------------------------------------- shifts

  ShiftRecord? openShift;

  /// Opens a till session for the signed-in user.
  Future<ShiftRecord?> startShift({double openingFloat = 0}) async {
    final user = currentUser;
    if (user == null) return null;
    if (openShift != null) return openShift;

    final id = await _db
        .into(_db.shifts)
        .insert(
          ShiftsCompanion.insert(
            userId: user.id,
            openingFloat: Value(openingFloat),
          ),
        );
    await _audit(
      'CREATE',
      'shifts',
      id,
      'Opened till with ${AppFormatters.currency(openingFloat)} float',
    );
    await refresh();
    return openShift;
  }

  /// Closes the session, storing the counted cash and what was expected so a
  /// closed shift never changes afterwards.
  Future<ShiftRecord?> endShift({
    required double countedCash,
    String? notes,
  }) async {
    final shift = openShift;
    if (shift == null) return null;

    final totals = await _shiftTotals(shift.id, shift.openedAt);
    final expected =
        shift.openingFloat +
        totals.cashSales +
        totals.paidIn -
        totals.cashRefunds -
        totals.paidOut;

    await (_db.update(_db.shifts)..where((s) => s.id.equals(shift.id))).write(
      ShiftsCompanion(
        closedAt: Value(DateTime.now()),
        closingCount: Value(_money(countedCash)),
        expectedCash: Value(_money(expected)),
        cashSales: Value(_money(totals.cashSales)),
        cardSales: Value(_money(totals.cardSales)),
        upiSales: Value(_money(totals.upiSales)),
        cashRefunds: Value(_money(totals.cashRefunds)),
        paidIn: Value(_money(totals.paidIn)),
        paidOut: Value(_money(totals.paidOut)),
        saleCount: Value(totals.saleCount),
        notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
      ),
    );
    final variance = _money(countedCash - expected);
    await _audit(
      'UPDATE',
      'shifts',
      shift.id,
      'Closed till. Counted ${AppFormatters.currency(countedCash)}, '
          'expected ${AppFormatters.currency(expected)}, '
          'difference ${AppFormatters.currency(variance)}',
    );
    await refresh();
    return shifts.where((s) => s.id == shift.id).firstOrNull;
  }

  /// Records money in or out of the drawer that was not a sale.
  Future<void> recordCashMovement({
    required bool isIn,
    required double amount,
    required String reason,
  }) async {
    final shift = openShift;
    if (shift == null || amount <= 0) return;
    await _db
        .into(_db.cashMovements)
        .insert(
          CashMovementsCompanion.insert(
            shiftId: shift.id,
            userId: Value(currentUser?.id),
            direction: isIn ? 'in' : 'out',
            amount: _money(amount),
            reason: reason.trim(),
          ),
        );
    await _audit(
      'CREATE',
      'cash_movements',
      shift.id,
      '${isIn ? 'Paid in' : 'Paid out'} ${AppFormatters.currency(amount)}: '
          '${reason.trim()}',
    );
    await refresh();
  }

  /// Live figures for the open session, for the X report.
  Future<ShiftRecord?> currentShiftWithTotals() async {
    final shift = openShift;
    if (shift == null) return null;
    final totals = await _shiftTotals(shift.id, shift.openedAt);
    return ShiftRecord(
      id: shift.id,
      userId: shift.userId,
      userName: shift.userName,
      openedAt: shift.openedAt,
      openingFloat: shift.openingFloat,
      cashSales: _money(totals.cashSales),
      cardSales: _money(totals.cardSales),
      upiSales: _money(totals.upiSales),
      cashRefunds: _money(totals.cashRefunds),
      paidIn: _money(totals.paidIn),
      paidOut: _money(totals.paidOut),
      saleCount: totals.saleCount,
    );
  }

  Future<_ShiftTotals> _shiftTotals(int shiftId, DateTime openedAt) async {
    final sales = await (_db.select(
      _db.sales,
    )..where((s) => s.shiftId.equals(shiftId))).get();

    var cash = 0.0, card = 0.0, upi = 0.0;
    for (final sale in sales) {
      cash += sale.cashAmount;
      card += sale.cardAmount;
      upi += sale.upiAmount;
    }

    // Returns are not stamped with a shift, so they are matched by time: any
    // cash refund since this session opened came out of this drawer.
    final refunds =
        await (_db.select(_db.returns)..where(
              (r) =>
                  r.refundMethod.equals('cash') &
                  r.returnedAt.isBiggerOrEqualValue(openedAt),
            ))
            .get();
    final cashRefunds = refunds.fold(0.0, (sum, r) => sum + r.totalAmount);

    final movements = await (_db.select(
      _db.cashMovements,
    )..where((m) => m.shiftId.equals(shiftId))).get();
    var paidIn = 0.0, paidOut = 0.0;
    for (final movement in movements) {
      if (movement.direction == 'in') {
        paidIn += movement.amount;
      } else {
        paidOut += movement.amount;
      }
    }

    return _ShiftTotals(
      cashSales: cash,
      cardSales: card,
      upiSales: upi,
      cashRefunds: cashRefunds,
      paidIn: paidIn,
      paidOut: paidOut,
      saleCount: sales.length,
    );
  }

  final shifts = <ShiftRecord>[];

  Future<void> _loadShifts() async {
    final names = {
      for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
    };
    final rows = await (_db.select(
      _db.shifts,
    )..orderBy([(s) => OrderingTerm.desc(s.openedAt)])).get();

    shifts
      ..clear()
      ..addAll(
        rows.map(
          (r) => ShiftRecord(
            id: r.id,
            userId: r.userId,
            userName: names[r.userId] ?? 'Unknown',
            openedAt: r.openedAt,
            closedAt: r.closedAt,
            openingFloat: r.openingFloat,
            closingCount: r.closingCount,
            expectedCash: r.expectedCash,
            cashSales: r.cashSales,
            cardSales: r.cardSales,
            upiSales: r.upiSales,
            cashRefunds: r.cashRefunds,
            paidIn: r.paidIn,
            paidOut: r.paidOut,
            saleCount: r.saleCount,
            notes: r.notes,
          ),
        ),
      );

    final mine = currentUser?.id;
    openShift = shifts
        .where((s) => s.isOpen && (mine == null || s.userId == mine))
        .firstOrNull;
  }

  Future<void> _seedFirstRunData() async {
    final rolesCount = await _db
        .select(_db.roles)
        .get()
        .then((rows) => rows.length);
    if (rolesCount == 0) {
      final adminRoleId = await _db
          .into(_db.roles)
          .insert(
            RolesCompanion.insert(
              name: 'Admin',
              description: const Value('Full system access'),
            ),
          );
      await _db
          .into(_db.roles)
          .insert(
            RolesCompanion.insert(
              name: 'Cashier',
              description: const Value('Point-of-sale access'),
            ),
          );
      await _db
          .into(_db.users)
          .insert(
            UsersCompanion.insert(
              fullName: 'Admin User',
              username: 'admin',
              passwordHash: _hash('admin123'),
              roleId: adminRoleId,
            ),
          );
    }
    if (await _db.select(_db.units).get().then((rows) => rows.isEmpty)) {
      await _db
          .into(_db.units)
          .insert(UnitsCompanion.insert(name: 'Pieces', abbreviation: 'pcs'));
    }
    if (await _db.select(_db.customers).get().then((rows) => rows.isEmpty)) {
      await _db
          .into(_db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Walk-in Customer',
              phone: const Value('-'),
              email: const Value('-'),
            ),
          );
    }
  }

  Future<void> _loadStoreProfile() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(storeProfileKey))).getSingleOrNull();
    storeProfile = row == null
        ? null
        : StoreProfile.fromJson(
            jsonDecode(row.valueJson) as Map<String, dynamic>,
          );
    // Every screen and every printed document formats money through
    // AppFormatters, so the configured symbol is applied once, here.
    AppFormatters.configure(
      symbol: storeProfile?.currencySymbol,
      locale: storeProfile?.currencyLocale,
    );
    // Repaint the palette from the shop's saved brand. Called every refresh
    // so a change under Settings takes on the next frame without having to
    // hot-restart. Missing profile falls back to the classic palette.
    AppColors.install(storeProfile?.brandTheme ?? BrandTheme.classic);
  }

  Future<void> _loadGstSettings() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(gstSettingsKey))).getSingleOrNull();
    gstSettings = row == null
        ? const GstSettings()
        : GstSettings.decode(row.valueJson);
  }

  Future<void> _loadPrinterSettings() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(printerSettingsKey))).getSingleOrNull();
    printerSettings = row == null
        ? const PrinterSettings()
        : PrinterSettings.decode(row.valueJson);
  }

  Future<void> savePrinterSettings(PrinterSettings settings) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: printerSettingsKey,
            valueJson: settings.encode(),
          ),
        );
    printerSettings = settings;
    await _audit('UPSERT', 'settings', null, 'Updated printer settings');
    notifyListeners();
  }

  Future<void> saveGstSettings(GstSettings settings) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: gstSettingsKey,
            valueJson: settings.encode(),
          ),
        );
    gstSettings = settings;
    await _audit('UPSERT', 'settings', null, 'Updated GST settings');
    notifyListeners();
  }

  Future<void> _loadLookups() async {
    final categories = await (_db.select(
      _db.categories,
    )..where((c) => c.isDeleted.equals(false))).get();
    final brands = await (_db.select(
      _db.brands,
    )..where((b) => b.isDeleted.equals(false))).get();
    final units = await (_db.select(
      _db.units,
    )..where((u) => u.isDeleted.equals(false))).get();
    categoryNames
      ..clear()
      ..addAll(categories.map((c) => c.name));
    brandNames
      ..clear()
      ..addAll(brands.map((b) => b.name));
    unitNames
      ..clear()
      ..addAll(units.map((u) => u.abbreviation));
  }

  Future<void> _loadProducts() async {
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c.name,
    };
    final brands = {
      for (final b in await _db.select(_db.brands).get()) b.id: b.name,
    };
    final units = {
      for (final u in await _db.select(_db.units).get()) u.id: u.abbreviation,
    };
    final suppliersById = {
      for (final s in await _db.select(_db.suppliers).get()) s.id: s.name,
    };
    _styleRows
      ..clear()
      ..addAll(await _db.select(_db.productStyles).get());

    final primaryImages = <int, String>{};
    for (final image in await _db.select(_db.productImages).get()) {
      if (image.isPrimary || !primaryImages.containsKey(image.productId)) {
        primaryImages[image.productId] = image.filePath;
      }
    }

    final rows = await _db.select(_db.products).get();
    products
      ..clear()
      ..addAll(
        rows
            .where((p) => p.isActive)
            .map(
              (p) => ProductRecord(
                id: p.id,
                sku: p.sku,
                name: p.name,
                category: categories[p.categoryId] ?? 'General',
                brand: brands[p.brandId] ?? 'Unbranded',
                unit: units[p.unitId] ?? 'pcs',
                stock: p.currentStock < 0 ? 0 : p.currentStock,
                minimumStock: p.minimumStock,
                purchasePrice: p.purchasePrice,
                sellingPrice: p.sellingPrice,
                barcode: p.barcode ?? '',
                location: p.location ?? '',
                description: p.description ?? '',
                supplier: suppliersById[p.supplierId] ?? '',
                supplierId: p.supplierId,
                wholesalePrice: p.wholesalePrice,
                taxRate: p.taxRate,
                maximumStock: p.maximumStock,
                expiryDate: p.expiryDate,
                styleId: p.styleId,
                size: p.size ?? '',
                color: p.color ?? '',
                hsnCode: p.hsnCode ?? '',
                imagePath: primaryImages[p.id],
              ),
            ),
      );
  }

  /// Groups the loaded variants under their style so the matrix editor and the
  /// catalogue can present one card per design.
  void _rebuildStyles() {
    final byStyle = <int, List<ProductRecord>>{};
    for (final product in products) {
      final styleId = product.styleId;
      if (styleId == null) continue;
      byStyle.putIfAbsent(styleId, () => <ProductRecord>[]).add(product);
    }

    styles
      ..clear()
      ..addAll(
        _styleRows
            .where((row) => row.isActive)
            .map(
              (row) => StyleRecord(
                id: row.id,
                styleCode: row.styleCode,
                name: row.name,
                description: row.description ?? '',
                hsnCode: row.hsnCode ?? '',
                season: row.season ?? '',
                purchasePrice: row.purchasePrice,
                sellingPrice: row.sellingPrice,
                active: row.isActive,
                variants: byStyle[row.id] ?? <ProductRecord>[],
              ),
            ),
      );

    sizeNames
      ..clear()
      ..addAll(
        StyleRecord._distinct(
          products.map((p) => p.size).where((s) => s.trim().isNotEmpty),
        ),
      );
    colorNames
      ..clear()
      ..addAll(
        StyleRecord._distinct(
          products.map((p) => p.color).where((c) => c.trim().isNotEmpty),
        ),
      );
  }

  Future<void> _loadCustomers() async {
    final rows = await (_db.select(
      _db.customers,
    )..where((c) => c.isDeleted.equals(false))).get();

    // What each customer has spent here, all-time. Read straight off the bills
    // so it agrees with the sales figures by construction; a stored running
    // total would only have to be repaired the first time a bill was voided.
    final spend = <int, double>{};
    final bills = <int, int>{};
    final lastSeen = <int, DateTime>{};
    for (final sale in await _db.select(_db.sales).get()) {
      final id = sale.customerId;
      if (id == null) continue;
      spend.update(
        id,
        (v) => v + sale.grandTotal,
        ifAbsent: () => sale.grandTotal,
      );
      bills.update(id, (v) => v + 1, ifAbsent: () => 1);
      final seen = lastSeen[id];
      if (seen == null || sale.soldAt.isAfter(seen)) lastSeen[id] = sale.soldAt;
    }

    customers
      ..clear()
      ..addAll(
        rows.map(
          (c) => CustomerRecord(
            id: c.id,
            name: c.name,
            phone: c.phone ?? '',
            email: c.email ?? '',
            address: c.address ?? '',
            creditLimit: c.creditLimit,
            openingBalance: c.openingBalance,
            balance: c.currentBalance,
            gstin: c.gstin ?? '',
            stateCode: c.stateCode ?? '',
            lifetimeSpend: _money(spend[c.id] ?? 0),
            lifetimeBills: bills[c.id] ?? 0,
            lastPurchaseAt: lastSeen[c.id],
          ),
        ),
      );
  }

  Future<void> _loadSuppliers() async {
    final rows = await (_db.select(
      _db.suppliers,
    )..where((s) => s.isDeleted.equals(false))).get();
    suppliers
      ..clear()
      ..addAll(
        rows.map(
          (s) => SupplierRecord(
            id: s.id,
            name: s.name,
            phone: s.phone ?? '',
            email: s.email ?? '',
            address: s.address ?? '',
            openingBalance: s.openingBalance,
            balance: s.currentBalance,
          ),
        ),
      );
  }

  Future<void> _loadSales() async {
    final customerNames = {
      for (final c in await _db.select(_db.customers).get()) c.id: c.name,
    };
    final rows = await (_db.select(
      _db.sales,
    )..orderBy([(s) => OrderingTerm.desc(s.soldAt)])).get();

    // Profit comes from the sale lines, which carry the cost captured at the
    // time of sale. Falling back to zero here — as this used to — made every
    // profit figure in the app read zero after a restart.
    final profitBySale = <int, double>{};
    for (final item in await _db.select(_db.saleItems).get()) {
      final lineProfit = item.taxableValue - (item.costPrice * item.quantity);
      profitBySale.update(
        item.saleId,
        (value) => value + lineProfit,
        ifAbsent: () => lineProfit,
      );
    }

    sales
      ..clear()
      ..addAll(
        rows.map(
          (s) => SaleRecord(
            receipt: s.receiptNumber,
            customerName: customerNames[s.customerId] ?? 'Walk-in',
            total: s.grandTotal,
            profit: _money(profitBySale[s.id] ?? 0),
            createdAt: s.soldAt,
            taxableValue: s.subtotal,
            cgst: s.cgstTotal,
            sgst: s.sgstTotal,
            igst: s.igstTotal,
            discountTotal: s.discountTotal,
            paymentMethod: s.paymentMethod,
            cashAmount: s.cashAmount,
            cardAmount: s.cardAmount,
            upiAmount: s.upiAmount,
            customerGstin: s.customerGstin,
            placeOfSupply: s.placeOfSupply,
          ),
        ),
      );
  }

  Future<void> _loadAuditLogs() async {
    final rows = await (_db.select(
      _db.auditLogs,
    )..orderBy([(a) => OrderingTerm.desc(a.createdAt)])).get();
    auditLogs
      ..clear()
      ..addAll(
        rows.map(
          (a) =>
              '${a.createdAt.toIso8601String()} [${a.action}] '
              '${a.payloadJson ?? a.entityType}',
        ),
      );
  }

  Future<int> _ensureUnit(String abbreviation) async {
    final normalized = abbreviation.trim().isEmpty
        ? 'pcs'
        : abbreviation.trim();
    final existing = await (_db.select(
      _db.units,
    )..where((u) => u.abbreviation.equals(normalized))).getSingleOrNull();
    return existing?.id ??
        _db
            .into(_db.units)
            .insert(
              UnitsCompanion.insert(name: normalized, abbreviation: normalized),
            );
  }

  Future<int?> _ensureCategory(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;
    final existing = await (_db.select(
      _db.categories,
    )..where((c) => c.name.equals(normalized))).getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.categories)
        .insert(CategoriesCompanion.insert(name: normalized));
  }

  Future<int?> _ensureBrand(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;
    final existing = await (_db.select(
      _db.brands,
    )..where((b) => b.name.equals(normalized))).getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.brands)
        .insert(BrandsCompanion.insert(name: normalized));
  }

  Future<int?> _ensureSupplier(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;
    final existing = await (_db.select(
      _db.suppliers,
    )..where((s) => s.name.equals(normalized))).getSingleOrNull();
    if (existing != null) return existing.id;
    return _db
        .into(_db.suppliers)
        .insert(SuppliersCompanion.insert(name: normalized));
  }

  Future<int> _adminUserId() async => (await (_db.select(
    _db.users,
  )..where((u) => u.username.equals('admin'))).getSingle()).id;

  Future<void> _audit(
    String action,
    String entityType,
    int? entityId,
    String message,
  ) async {
    auditLogs.insert(
      0,
      '${DateTime.now().toIso8601String()} [$action] $message',
    );
    await _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            userId: Value(currentUser?.id),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            payloadJson: Value(jsonEncode({'message': message})),
          ),
        );
  }

  /// Reconstructs the printable invoice for a past sale, so a bill can be
  /// re-opened from the bills list or a statement row and re-printed.
  ///
  /// The line rows keep their own taxable value and tax at sale time; a
  /// product renamed since still resolves to a friendly description via a
  /// small batched name lookup rather than a query per line.
  Future<InvoiceData?> loadInvoiceForReceipt(String receipt) async {
    final row = await (_db.select(
      _db.sales,
    )..where((s) => s.receiptNumber.equals(receipt.trim()))).getSingleOrNull();
    if (row == null) return null;
    final items = await (_db.select(
      _db.saleItems,
    )..where((i) => i.saleId.equals(row.id))).get();
    final productIds = {for (final i in items) i.productId};
    final products = productIds.isEmpty
        ? const <int, ProductRow>{}
        : {
            for (final p in await (_db.select(
              _db.products,
            )..where((p) => p.id.isIn(productIds))).get())
              p.id: p,
          };
    final customerRow = row.customerId == null
        ? null
        : await (_db.select(
            _db.customers,
          )..where((c) => c.id.equals(row.customerId!))).getSingleOrNull();

    String label(int id) {
      final p = products[id];
      if (p == null) return 'Removed product';
      final v = [
        (p.color ?? '').trim(),
        (p.size ?? '').trim(),
      ].where((s) => s.isNotEmpty).join(' / ');
      return v.isEmpty ? p.name : '${p.name} ($v)';
    }

    final interState = (row.igstTotal) > 0;
    final lines = <InvoiceLine>[
      for (final i in items)
        InvoiceLine(
          description: label(i.productId),
          hsnCode: i.hsnCode ?? '',
          quantity: i.quantity.toInt(),
          unitPrice: i.unitPrice,
          discount: i.discountAmount,
          taxableValue: i.taxableValue,
          taxRate: i.taxRate,
          cgst: interState ? 0 : i.taxAmount / 2,
          sgst: interState ? 0 : i.taxAmount / 2,
          igst: interState ? i.taxAmount : 0,
          lineTotal: i.lineTotal,
        ),
    ];

    final sale = SaleRecord(
      receipt: row.receiptNumber,
      customerName: customerRow?.name ?? 'Walk-in',
      total: row.grandTotal,
      profit: 0,
      createdAt: row.soldAt,
      taxableValue: row.subtotal,
      cgst: row.cgstTotal,
      sgst: row.sgstTotal,
      igst: row.igstTotal,
      discountTotal: row.discountTotal,
      paymentMethod: row.paymentMethod,
      cashAmount: row.cashAmount,
      cardAmount: row.cardAmount,
      upiAmount: row.upiAmount,
      customerGstin: row.customerGstin,
      placeOfSupply: row.placeOfSupply,
    );

    final paymentLabel = switch (row.paymentMethod) {
      'cash' => 'Paid by cash',
      'card' => 'Paid by card',
      'upi' => 'Paid by UPI',
      'split' =>
        'Split: cash ${AppFormatters.currency(row.cashAmount)}, '
            'card ${AppFormatters.currency(row.cardAmount)}, '
            'UPI ${AppFormatters.currency(row.upiAmount)}',
      _ => 'Paid',
    };

    return InvoiceData(
      sale: sale,
      lines: lines,
      profile: storeProfile,
      paid: row.paidAmount,
      change: 0,
      paymentLabel: paymentLabel,
      customerName: customerRow?.name,
      customerPhone: customerRow?.phone,
      customerAddress: customerRow?.address,
    );
  }

  /// Wipes the shop's trading history, leaving the setup behind.
  ///
  /// This is the "we were testing, now we are opening" button. It clears
  /// bills, returns, deliveries, expenses, payments, till sessions, held
  /// bills, stock movements and the audit log, and puts every product's stock
  /// back to zero — but keeps the catalogue, the customers, the suppliers,
  /// the staff accounts and everything under Settings, because typing those
  /// in again is the part nobody wants to repeat.
  ///
  /// [alsoParties] additionally clears customers and suppliers, for a shop
  /// that entered fake ones while testing. [alsoCatalogue] clears the products
  /// and designs too, which is as close to a factory reset as this gets while
  /// still keeping the shop profile and the login.
  ///
  /// The invoice counter is reset so the first real bill is number one.
  Future<void> resetTradingData({
    bool alsoParties = false,
    bool alsoCatalogue = false,
  }) async {
    await _db.transaction(() async {
      // Children before parents: foreign keys are on.
      await _db.delete(_db.saleItems).go();
      await _db.delete(_db.returnItems).go();
      await _db.delete(_db.returns).go();
      await _db.delete(_db.sales).go();
      await _db.delete(_db.purchaseItems).go();
      await _db.delete(_db.purchases).go();
      await _db.delete(_db.heldBillItems).go();
      await _db.delete(_db.heldBills).go();
      await _db.delete(_db.cashMovements).go();
      await _db.delete(_db.shifts).go();
      await _db.delete(_db.partyPayments).go();
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.inventoryMovements).go();
      await _db.delete(_db.ledgerEntries).go();
      await _db.delete(_db.cashBook).go();
      await _db.delete(_db.bankBook).go();
      await _db.delete(_db.auditLogs).go();

      // Balances are derived from the rows just deleted, so they go to zero
      // rather than being left quoting money nobody owes any more.
      await _db
          .update(_db.customers)
          .write(const CustomersCompanion(currentBalance: Value(0)));
      await _db
          .update(_db.suppliers)
          .write(const SuppliersCompanion(currentBalance: Value(0)));
      await _db
          .update(_db.products)
          .write(const ProductsCompanion(currentStock: Value(0)));

      if (alsoCatalogue) {
        await _db.delete(_db.productImages).go();
        await _db.delete(_db.products).go();
        await _db.delete(_db.productStyles).go();
      }
      if (alsoParties) {
        await _db.delete(_db.customers).go();
        await _db.delete(_db.suppliers).go();
      }

      // Start the numbering over, so the first real bill is 0001.
      await (_db.delete(
        _db.settings,
      )..where((s) => s.key.equals(invoiceCounterKey))).go();
    });

    cart.clear();
    _billDiscount = 0;
    await refresh();
    await _audit(
      'DELETE',
      'settings',
      null,
      'Reset trading data'
          '${alsoParties ? ' + customers/suppliers' : ''}'
          '${alsoCatalogue ? ' + catalogue' : ''}',
    );
    notifyListeners();
  }

  Future<Directory> _appDataDirectory() async {
    final directory = await getApplicationSupportDirectory();
    final dbFolder = Directory(p.join(directory.path, 'ClassyCloset'));
    if (!dbFolder.existsSync()) dbFolder.createSync(recursive: true);
    return dbFolder;
  }

  bool _today(SaleRecord sale) {
    final now = DateTime.now();
    return sale.createdAt.year == now.year &&
        sale.createdAt.month == now.month &&
        sale.createdAt.day == now.day;
  }

  String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();
  AppRole _roleFromName(String? name) => AppRole.fromName(name);
}

/// Running totals for one till session.
class _ShiftTotals {
  const _ShiftTotals({
    required this.cashSales,
    required this.cardSales,
    required this.upiSales,
    required this.cashRefunds,
    required this.paidIn,
    required this.paidOut,
    required this.saleCount,
  });

  final double cashSales;
  final double cardSales;
  final double upiSales;
  final double cashRefunds;
  final double paidIn;
  final double paidOut;
  final int saleCount;
}

/// Running tax totals for one GST rate.
class _RateBucket {
  double taxable = 0, cgst = 0, sgst = 0, igst = 0;
  int count = 0;

  void add(double taxableValue, double tax, bool isIgst) {
    taxable += taxableValue;
    if (isIgst) {
      igst += tax;
    } else {
      cgst += tax / 2;
      sgst += tax / 2;
    }
    count++;
  }
}

/// Running totals for one HSN code.
class _HsnBucket {
  _HsnBucket(this.description);
  final String description;
  double quantity = 0, taxable = 0, tax = 0;

  void add(double qty, double taxableValue, double taxAmount) {
    quantity += qty;
    taxable += taxableValue;
    tax += taxAmount;
  }
}

/// Running totals for one product.
class _ProductBucket {
  _ProductBucket(this.description, this.stockOnHand);
  final String description;
  final double stockOnHand;
  double quantity = 0, revenue = 0, profit = 0;

  void add(double qty, double lineTotal, double lineProfit) {
    quantity += qty;
    revenue += lineTotal;
    profit += lineProfit;
  }
}

/// One line of a goods receipt: how many arrived and what each cost.
class PurchaseLine {
  const PurchaseLine({required this.quantity, required this.unitCost});
  final double quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;
}

/// A recorded delivery.
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.invoiceNumber,
    required this.supplierId,
    required this.supplierName,
    required this.total,
    required this.paid,
    required this.purchasedAt,
    this.settled = 0,
    this.invoicePath,
    this.lineCount = 0,
  });

  final int id;
  final String invoiceNumber;
  final int supplierId;
  final String supplierName;
  final double total;

  /// Handed over on the day the delivery was booked.
  final double paid;

  /// Settled since, out of payments recorded against the supplier's account.
  final double settled;

  /// The supplier's own invoice, scanned or photographed.
  final String? invoicePath;
  final DateTime purchasedAt;
  final int lineCount;

  /// Everything that has reached the supplier for this delivery, whenever it
  /// went. This is the figure the deliveries table shows as PAID, so paying a
  /// balance off on the Suppliers screen is visible here too.
  double get totalPaid => paid + settled;
  double get outstanding => total - totalPaid;
  bool get hasInvoiceFile => (invoicePath ?? '').trim().isNotEmpty;
}

/// Money the shop spent that was not stock.
class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.amount,
    required this.spentAt,
    this.notes,
  });

  final int id;
  final String category;
  final String title;
  final double amount;
  final DateTime spentAt;
  final String? notes;
}

/// A one-shot summary of every figure the till and the checkout need.
///
/// Kept as a value so the pinned footer and the checkout share one pass over
/// the cart — the pinned footer would otherwise recompute the same slab-wise
/// GST arithmetic five times per rebuild for no gain.
class CartTotals {
  const CartTotals({
    required this.gross,
    required this.billDiscount,
    required this.lineDiscount,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
  });

  /// Sum of the shelf prices before any discount.
  final double gross;

  /// The flat amount taken off the whole bill.
  final double billDiscount;

  /// Sum of any per-line discounts (unused by the till today).
  final double lineDiscount;

  /// Value the tax is charged on — the discounted net less its own GST.
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;

  /// What the customer pays.
  final double total;

  double get discountTotal => billDiscount + lineDiscount;
  double get taxTotal => cgst + sgst + igst;
}

/// Scratch slab used while allocating the bill discount across GST rates.
class _RateBasket {
  double gross = 0;
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../utils/formatters.dart';
import 'gst.dart';
import 'permissions.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.isActive = true,
  });
  final int id;
  final String name;
  final String username;
  final AppRole role;
  final bool isActive;

  Set<Permission> get permissions => permissionsFor(role);
  bool can(Permission permission) => permissions.contains(permission);
}

class StoreProfile {
  const StoreProfile({
    required this.storeName,
    required this.currencySymbol,
    this.logoPath,
    this.address,
    this.phone,
    this.email,
    this.taxRegistrationNumber,
    this.receiptFooterText,
    this.receiptNumberPrefix = '',
    this.gstin,
    this.stateCode,
    this.currencyLocale = 'en_IN',
  });

  final String storeName;
  final String currencySymbol;
  final String? logoPath;
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
    'address': address,
    'phone': phone,
    'email': email,
    'taxRegistrationNumber': taxRegistrationNumber,
    'receiptFooterText': receiptFooterText,
    'receiptNumberPrefix': receiptNumberPrefix,
    'gstin': gstin,
    'stateCode': stateCode,
    'currencyLocale': currencyLocale,
  };

  factory StoreProfile.fromJson(Map<String, dynamic> json) => StoreProfile(
    storeName: (json['storeName'] as String? ?? '').trim(),
    currencySymbol: (json['currencySymbol'] as String? ?? '₹').trim(),
    logoPath: json['logoPath'] as String?,
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    taxRegistrationNumber: json['taxRegistrationNumber'] as String?,
    receiptFooterText: json['receiptFooterText'] as String?,
    receiptNumberPrefix: (json['receiptNumberPrefix'] as String? ?? '').trim(),
    gstin: (json['gstin'] as String?)?.trim(),
    stateCode: (json['stateCode'] as String?)?.trim(),
    currencyLocale: (json['currencyLocale'] as String? ?? 'en_IN').trim(),
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
  });
  final int id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final double creditLimit;
  final double openingBalance;
  double balance;

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
  final ProductRecord product;
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
  static const invoiceCounterKey = 'invoice_counter';

  final AppDatabase _db;
  AppUser? currentUser;
  StoreProfile? storeProfile;
  GstSettings gstSettings = const GstSettings();
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
      _loadLookups(),
      _loadSuppliers(),
      _loadProducts(),
      _loadCustomers(),
      _loadSales(),
      _loadAuditLogs(),
      _loadUsers(),
    ]);
    _rebuildStyles();
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
          ),
        ),
      );
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

  Future<String?> copyLogoToAppFolder(String? sourcePath) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath);
    if (!source.existsSync()) return sourcePath;
    final directory = await _appDataDirectory();
    final extension = p.extension(source.path).isEmpty
        ? '.png'
        : p.extension(source.path);
    final target = File(p.join(directory.path, 'store_logo$extension'));
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
        currentStock: Value(product.stock),
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
        if (product.stock != 0) {
          await _db
              .into(_db.inventoryMovements)
              .insert(
                InventoryMovementsCompanion.insert(
                  productId: productId,
                  movementType: 'opening',
                  quantity: product.stock,
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
          currentStock: Value(variant.stock),
          minimumStock: Value(variant.minimumStock),
          location: Value(
            variant.location.trim().isEmpty ? null : variant.location.trim(),
          ),
          isActive: const Value(true),
        );

        if (match == null) {
          final id = await _db.into(_db.products).insert(row);
          keptIds.add(id);
          if (variant.stock != 0) {
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion.insert(
                    productId: id,
                    movementType: 'opening',
                    quantity: variant.stock,
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
        'product_${productId}_${DateTime.now().millisecondsSinceEpoch}$extension',
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

  void addToCart(ProductRecord product) {
    final existing = cart
        .where((line) => line.product.id == product.id)
        .cast<CartLine?>()
        .firstOrNull;
    if (existing == null) {
      cart.add(CartLine(product: product, quantity: 1));
    } else {
      existing.quantity++;
    }
    notifyListeners();
  }

  void removeFromCart(CartLine line) {
    cart.remove(line);
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
  /// With tax-inclusive pricing — the Indian retail norm — this is just the sum
  /// of the line totals, because GST is already inside the shelf price. With
  /// tax-exclusive pricing the tax is added on top.
  double cartGrandTotal({CustomerRecord? customer}) {
    var total = 0.0;
    for (final line in cart) {
      final tax = lineTaxFor(line, customer: customer);
      total += gstSettings.pricesIncludeTax ? line.total : tax.grossValue;
    }
    return _money(total);
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
    final taxes = [
      for (final line in snapshot) lineTaxFor(line, customer: customer),
    ];

    var taxableTotal = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0;
    var grandTotal = 0.0, discountTotal = 0.0, costTotal = 0.0;
    for (var i = 0; i < snapshot.length; i++) {
      final line = snapshot[i];
      final tax = taxes[i];
      taxableTotal += tax.taxableValue;
      cgst += tax.cgst;
      sgst += tax.sgst;
      igst += tax.igst;
      discountTotal += line.discount;
      costTotal += line.cost;
      grandTotal += gstSettings.pricesIncludeTax ? line.total : tax.grossValue;
    }
    taxableTotal = _money(taxableTotal);
    cgst = _money(cgst);
    sgst = _money(sgst);
    igst = _money(igst);
    grandTotal = _money(grandTotal);

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
                discountAmount: Value(line.discount),
                taxAmount: Value(tax.taxAmount),
                lineTotal: gstSettings.pricesIncludeTax
                    ? line.total
                    : tax.grossValue,
                hsnCode: Value(_hsnFor(line.product)),
                taxRate: Value(tax.ratePercent),
                taxableValue: Value(tax.taxableValue),
                costPrice: Value(line.product.purchasePrice),
              ),
            );
        final after = line.product.stock - line.quantity;
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

    final prefix = storeProfile?.receiptNumberPrefix.trim().isNotEmpty == true
        ? storeProfile!.receiptNumberPrefix.trim()
        : 'INV';
    // Rule 46 caps the invoice number at 16 characters.
    final candidate = '$prefix/$label/${next.toString().padLeft(4, '0')}';
    return candidate.length <= 16
        ? candidate
        : candidate.substring(candidate.length - 16);
  }

  static double _money(double value) => (value * 100).roundToDouble() / 100;

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
  }

  Future<void> _loadGstSettings() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(gstSettingsKey))).getSingleOrNull();
    gstSettings = row == null
        ? const GstSettings()
        : GstSettings.decode(row.valueJson);
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
                stock: p.currentStock,
                minimumStock: p.minimumStock,
                purchasePrice: p.purchasePrice,
                sellingPrice: p.sellingPrice,
                barcode: p.barcode ?? '',
                location: p.location ?? '',
                description: p.description ?? '',
                supplier: suppliersById[p.supplierId] ?? '',
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
              '${a.createdAt.toIso8601String()} [${a.action}] ${a.payloadJson ?? a.entityType}',
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

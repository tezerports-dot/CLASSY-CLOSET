import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../utils/formatters.dart';

enum UserRole { admin, manager, cashier, storeKeeper, sales }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
  });
  final int id;
  final String name;
  final String username;
  final UserRole role;
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
  };

  factory StoreProfile.fromJson(Map<String, dynamic> json) => StoreProfile(
    storeName: (json['storeName'] as String? ?? '').trim(),
    currencySymbol: (json['currencySymbol'] as String? ?? r'$').trim(),
    logoPath: json['logoPath'] as String?,
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    taxRegistrationNumber: json['taxRegistrationNumber'] as String?,
    receiptFooterText: json['receiptFooterText'] as String?,
    receiptNumberPrefix: (json['receiptNumberPrefix'] as String? ?? '').trim(),
  );
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

  double get stockValue => stock * purchasePrice;
  bool get lowStock => stock <= minimumStock;
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
  });
  final int id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final double creditLimit;
  final double openingBalance;
  double balance;
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
  });
  final String receipt;
  final String customerName;
  final double total;
  final double profit;
  final DateTime createdAt;
}

class CartLine {
  CartLine({required this.product, required this.quantity});
  final ProductRecord product;
  int quantity;
  double get total => quantity * product.sellingPrice;
  double get profit =>
      quantity * (product.sellingPrice - product.purchasePrice);
}

class RetailStore extends ChangeNotifier {
  RetailStore(this._db);

  static const storeProfileKey = 'store_profile';

  final AppDatabase _db;
  AppUser? currentUser;
  StoreProfile? storeProfile;
  final products = <ProductRecord>[];
  final customers = <CustomerRecord>[];
  final suppliers = <SupplierRecord>[];
  final categoryNames = <String>[];
  final brandNames = <String>[];
  final unitNames = <String>[];
  final sales = <SaleRecord>[];
  final cart = <CartLine>[];
  final auditLogs = <String>[];
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

  Future<void> initialize() async {
    if (_initialized) return;
    await _seedFirstRunData();
    await refresh();
    _initialized = true;
  }

  Future<void> refresh() async {
    await Future.wait([
      _loadStoreProfile(),
      _loadLookups(),
      _loadSuppliers(),
      _loadProducts(),
      _loadCustomers(),
      _loadSales(),
      _loadAuditLogs(),
    ]);
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

  Future<SaleRecord> checkout({
    CustomerRecord? customer,
    double paid = 0,
    String paymentMethod = 'cash',
    double cashAmount = 0,
    double cardAmount = 0,
  }) async {
    final snapshot = List<CartLine>.from(cart);
    final total = snapshot.fold(0.0, (sum, line) => sum + line.total);
    final profit = snapshot.fold(0.0, (sum, line) => sum + line.profit);
    final receiptPrefix =
        storeProfile?.receiptNumberPrefix.trim().isNotEmpty == true
        ? storeProfile!.receiptNumberPrefix.trim()
        : 'R';
    final receipt = '$receiptPrefix-${DateTime.now().millisecondsSinceEpoch}';
    late SaleRecord sale;
    await _db.transaction(() async {
      final saleId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              customerId: Value(customer?.id),
              userId: currentUser?.id ?? await _adminUserId(),
              receiptNumber: receipt,
              subtotal: Value(total),
              grandTotal: Value(total),
              paidAmount: Value(paid),
              paymentMethod: Value(paymentMethod),
              cashAmount: Value(cashAmount),
              cardAmount: Value(cardAmount),
            ),
          );
      for (final line in snapshot) {
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: line.product.id,
                quantity: line.quantity.toDouble(),
                unitPrice: line.product.sellingPrice,
                lineTotal: line.total,
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
      if (customer != null && paid < total) {
        await (_db.update(
          _db.customers,
        )..where((c) => c.id.equals(customer.id))).write(
          CustomersCompanion(
            currentBalance: Value(customer.balance + total - paid),
          ),
        );
      }
      await _audit(
        'CREATE',
        'sales',
        saleId,
        'Completed $receipt for ${AppFormatters.currency(total)}',
      );
      sale = SaleRecord(
        receipt: receipt,
        customerName: customer?.name ?? 'Walk-in',
        total: total,
        profit: profit,
        createdAt: DateTime.now(),
      );
    });
    cart.clear();
    await refresh();
    return sale;
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
              ),
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
    sales
      ..clear()
      ..addAll(
        rows.map(
          (s) => SaleRecord(
            receipt: s.receiptNumber,
            customerName: customerNames[s.customerId] ?? 'Walk-in',
            total: s.grandTotal,
            profit: 0,
            createdAt: s.soldAt,
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
  UserRole _roleFromName(String? name) => switch (name?.toLowerCase()) {
    'cashier' => UserRole.cashier,
    'manager' => UserRole.manager,
    'storekeeper' => UserRole.storeKeeper,
    'sales' => UserRole.sales,
    _ => UserRole.admin,
  };
}

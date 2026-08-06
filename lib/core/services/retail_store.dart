import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../utils/formatters.dart';

enum UserRole { admin, manager, cashier, storeKeeper, sales }

class AppUser {
  const AppUser({required this.id, required this.name, required this.username, required this.role});
  final int id;
  final String name;
  final String username;
  final UserRole role;
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
  final bool active;

  double get stockValue => stock * purchasePrice;
  bool get lowStock => stock <= minimumStock;
}

class CustomerRecord {
  CustomerRecord({required this.id, required this.name, required this.phone, required this.email, required this.creditLimit, this.balance = 0});
  final int id;
  final String name;
  final String phone;
  final String email;
  final double creditLimit;
  double balance;
}

class SupplierRecord {
  SupplierRecord({required this.id, required this.name, required this.phone, required this.email, this.balance = 0});
  final int id;
  final String name;
  final String phone;
  final String email;
  double balance;
}

class SaleRecord {
  SaleRecord({required this.receipt, required this.customerName, required this.total, required this.profit, required this.createdAt});
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
  double get profit => quantity * (product.sellingPrice - product.purchasePrice);
}

class RetailStore extends ChangeNotifier {
  RetailStore() {
    _seed();
  }

  final Map<String, String> _passwordHashes = {};
  AppUser? currentUser;
  final products = <ProductRecord>[];
  final customers = <CustomerRecord>[];
  final suppliers = <SupplierRecord>[];
  final sales = <SaleRecord>[];
  final cart = <CartLine>[];
  final auditLogs = <String>[];

  bool get isAuthenticated => currentUser != null;
  double get todaySales => sales.where(_today).fold(0, (sum, sale) => sum + sale.total);
  double get todayProfit => sales.where(_today).fold(0, (sum, sale) => sum + sale.profit);
  double get inventoryValue => products.fold(0, (sum, product) => sum + product.stockValue);
  Iterable<ProductRecord> get lowStockProducts => products.where((product) => product.lowStock);
  Iterable<CustomerRecord> get pendingCustomers => customers.where((customer) => customer.balance > 0);

  bool login(String username, String password) {
    final expected = _passwordHashes[username.trim().toLowerCase()];
    if (expected == null || expected != _hash(password)) return false;
    currentUser = AppUser(id: 1, name: 'Admin User', username: username, role: UserRole.admin);
    _audit('AUTH', 'Signed in as $username');
    notifyListeners();
    return true;
  }

  void logout() {
    _audit('AUTH', 'Signed out');
    currentUser = null;
    notifyListeners();
  }

  void addProduct(ProductRecord product) {
    products.add(product);
    _audit('PRODUCT', 'Created ${product.sku} ${product.name}');
    notifyListeners();
  }

  void addCustomer(CustomerRecord customer) {
    customers.add(customer);
    _audit('CUSTOMER', 'Created ${customer.name}');
    notifyListeners();
  }

  void addToCart(ProductRecord product) {
    CartLine? existing;
    for (final line in cart) {
      if (line.product.id == product.id) {
        existing = line;
        break;
      }
    }
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

  SaleRecord checkout({CustomerRecord? customer, double paid = 0}) {
    final total = cart.fold(0.0, (sum, line) => sum + line.total);
    final profit = cart.fold(0.0, (sum, line) => sum + line.profit);
    for (final line in cart) {
      line.product.stock -= line.quantity;
    }
    if (customer != null && paid < total) {
      customer.balance += total - paid;
    }
    final receipt = 'R-${DateTime.now().millisecondsSinceEpoch}';
    final sale = SaleRecord(
      receipt: receipt,
      customerName: customer?.name ?? 'Walk-in',
      total: total,
      profit: profit,
      createdAt: DateTime.now(),
    );
    sales.insert(0, sale);
    cart.clear();
    _audit('SALE', 'Completed $receipt for ${AppFormatters.currency(total)}');
    notifyListeners();
    return sale;
  }

  void _seed() {
    _passwordHashes['admin'] = _hash('admin123');
    products.addAll([
      ProductRecord(id: 1, sku: 'SKU-1001', name: 'Premium Shirt', category: 'Apparel', brand: 'Classy', unit: 'pcs', stock: 14, minimumStock: 5, purchasePrice: 18, sellingPrice: 35, barcode: '890100000001', location: 'A-01'),
      ProductRecord(id: 2, sku: 'SKU-1002', name: 'Slim Fit Jeans', category: 'Apparel', brand: 'DenimPro', unit: 'pcs', stock: 4, minimumStock: 6, purchasePrice: 28, sellingPrice: 59, barcode: '890100000002', location: 'A-03'),
      ProductRecord(id: 3, sku: 'SKU-1003', name: 'Leather Belt', category: 'Accessories', brand: 'Classy', unit: 'pcs', stock: 22, minimumStock: 8, purchasePrice: 7, sellingPrice: 19, barcode: '890100000003', location: 'B-02'),
    ]);
    customers.addAll([
      CustomerRecord(id: 1, name: 'Walk-in Customer', phone: '-', email: '-', creditLimit: 0),
      CustomerRecord(id: 2, name: 'Amelia Johnson', phone: '555-0133', email: 'amelia@example.com', creditLimit: 500, balance: 72),
    ]);
    suppliers.addAll([
      SupplierRecord(id: 1, name: 'North Apparel Supply', phone: '555-0177', email: 'orders@north.example', balance: 310),
      SupplierRecord(id: 2, name: 'City Accessories', phone: '555-0199', email: 'sales@city.example'),
    ]);
    sales.add(SaleRecord(receipt: 'R-DEMO-001', customerName: 'Amelia Johnson', total: 149, profit: 61, createdAt: DateTime.now()));
  }

  bool _today(SaleRecord sale) {
    final now = DateTime.now();
    return sale.createdAt.year == now.year && sale.createdAt.month == now.month && sale.createdAt.day == now.day;
  }

  String _hash(String password) => sha256.convert(utf8.encode(password)).toString();
  void _audit(String type, String message) => auditLogs.insert(0, '${DateTime.now().toIso8601String()} [$type] $message');
}

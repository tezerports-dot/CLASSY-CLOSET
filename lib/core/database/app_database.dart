import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('UserRow')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fullName => text().withLength(min: 1, max: 120)();
  TextColumn get username => text().unique().withLength(min: 3, max: 64)();
  TextColumn get passwordHash => text().withLength(min: 64, max: 64)();
  IntColumn get roleId => integer().references(Roles, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('RoleRow')
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique().withLength(min: 2, max: 48)();
  TextColumn get description => text().nullable()();
}

@DataClassName('PermissionRow')
class Permissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique().withLength(min: 3, max: 80)();
  TextColumn get description => text().nullable()();
}

@DataClassName('RolePermissionRow')
class RolePermissions extends Table {
  IntColumn get roleId => integer().references(Roles, #id, onDelete: KeyAction.cascade)();
  IntColumn get permissionId => integer().references(Permissions, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get colorHex => text().nullable()();
  TextColumn get iconName => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('BrandRow')
class Brands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique().withLength(min: 1, max: 100)();
  TextColumn get logoPath => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('UnitRow')
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique().withLength(min: 1, max: 40)();
  TextColumn get abbreviation => text().withLength(min: 1, max: 12)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('SupplierRow')
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 140)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('ProductRow')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().unique().withLength(min: 1, max: 64)();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get qrCode => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get brandId => integer().nullable().references(Brands, #id)();
  IntColumn get unitId => integer().references(Units, #id)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  RealColumn get purchasePrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  RealColumn get wholesalePrice => real().withDefault(const Constant(0))();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get currentStock => real().withDefault(const Constant(0))();
  RealColumn get minimumStock => real().withDefault(const Constant(0))();
  RealColumn get maximumStock => real().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('ProductImageRow')
class ProductImages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get filePath => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
}

@DataClassName('CustomerRow')
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 140)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('InventoryMovementRow')
class InventoryMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get movementType => text().withLength(min: 1, max: 32)();
  RealColumn get quantity => real()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseRow')
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  TextColumn get invoiceNumber => text().unique()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get taxTotal => real().withDefault(const Constant(0))();
  RealColumn get grandTotal => real().withDefault(const Constant(0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  DateTimeColumn get purchasedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseItemRow')
class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitCost => real()();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();
}

@DataClassName('SaleRow')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get receiptNumber => text().unique()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discountTotal => real().withDefault(const Constant(0))();
  RealColumn get taxTotal => real().withDefault(const Constant(0))();
  RealColumn get grandTotal => real().withDefault(const Constant(0))();
  RealColumn get paidAmount => real().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  RealColumn get cashAmount => real().withDefault(const Constant(0))();
  RealColumn get cardAmount => real().withDefault(const Constant(0))();
  DateTimeColumn get soldAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleItemRow')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();
}

@DataClassName('ReturnRow')
class Returns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  TextColumn get returnNumber => text().unique()();
  RealColumn get totalAmount => real().withDefault(const Constant(0))();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get returnedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ReturnItemRow')
class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(Returns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get refundAmount => real()();
}

@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('ExpenseRow')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(ExpenseCategories, #id)();
  TextColumn get title => text()();
  RealColumn get amount => real()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get spentAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CashBookRow')
class CashBook extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryType => text()();
  RealColumn get amount => real()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('BankBookRow')
class BankBook extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountName => text()();
  TextColumn get entryType => text()();
  RealColumn get amount => real()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('LedgerEntryRow')
class LedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountType => text()();
  IntColumn get accountId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  RealColumn get debit => real().withDefault(const Constant(0))();
  RealColumn get credit => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('AuditLogRow')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  Users,
  Roles,
  Permissions,
  RolePermissions,
  Categories,
  Brands,
  Units,
  Products,
  ProductImages,
  Customers,
  Suppliers,
  InventoryMovements,
  Purchases,
  PurchaseItems,
  Sales,
  SaleItems,
  Returns,
  ReturnItems,
  Expenses,
  ExpenseCategories,
  CashBook,
  BankBook,
  LedgerEntries,
  AuditLogs,
  Settings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final dbFolder = Directory(p.join(directory.path, 'ClassyCloset'));
    if (!dbFolder.existsSync()) {
      dbFolder.createSync(recursive: true);
    }
    final file = File(p.join(dbFolder.path, 'retailpro.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

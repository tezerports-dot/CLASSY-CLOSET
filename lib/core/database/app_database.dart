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
  IntColumn get roleId =>
      integer().references(Roles, #id, onDelete: KeyAction.cascade)();
  IntColumn get permissionId =>
      integer().references(Permissions, #id, onDelete: KeyAction.cascade)();

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

/// A design — the thing a customer points at. Its sellable units live in
/// [Products], one row per size/colour combination, so a single style can carry
/// a whole size run without duplicating the design's own attributes.
@DataClassName('ProductStyleRow')
class ProductStyles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get styleCode => text().unique().withLength(min: 1, max: 64)();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get brandId => integer().nullable().references(Brands, #id)();
  IntColumn get unitId => integer().references(Units, #id)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();

  /// Harmonised System code printed on the GST invoice. Chapter 61 covers
  /// knitted apparel, 62 woven.
  TextColumn get hsnCode => text().nullable()();
  TextColumn get season => text().nullable()();
  RealColumn get purchasePrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductRow')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The design this unit belongs to. Null means a standalone item that has no
  /// size or colour run of its own.
  IntColumn get styleId =>
      integer().nullable().references(ProductStyles, #id)();
  TextColumn get size => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get hsnCode => text().nullable()();
  TextColumn get sku => text().unique().withLength(min: 1, max: 64)();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get qrCode => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 180)();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
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
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
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

  /// Set for B2B buyers so the invoice can carry their GSTIN. The state code
  /// decides whether a sale is taxed as CGST+SGST or as IGST.
  TextColumn get gstin => text().nullable()();
  TextColumn get stateCode => text().nullable()();
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
  DateTimeColumn get purchasedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseItemRow')
class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId =>
      integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
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
  RealColumn get upiAmount => real().withDefault(const Constant(0))();

  /// GST is split at sale time and stored, so a reprinted invoice always shows
  /// the tax that was actually charged even if rates change later.
  RealColumn get cgstTotal => real().withDefault(const Constant(0))();
  RealColumn get sgstTotal => real().withDefault(const Constant(0))();
  RealColumn get igstTotal => real().withDefault(const Constant(0))();
  TextColumn get placeOfSupply => text().nullable()();
  TextColumn get customerGstin => text().nullable()();

  /// The till session this sale belongs to, so the drawer can be reconciled.
  IntColumn get shiftId => integer().nullable().references(Shifts, #id)();
  DateTimeColumn get soldAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleItemRow')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discountAmount => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get lineTotal => real()();

  /// Denormalised at sale time: Rule 46 requires the HSN code and rate that
  /// applied to each line, and both can change after the sale.
  TextColumn get hsnCode => text().nullable()();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get taxableValue => real().withDefault(const Constant(0))();

  /// Cost at the moment of sale, so profit reporting never depends on the
  /// product's current purchase price.
  RealColumn get costPrice => real().withDefault(const Constant(0))();
}

@DataClassName('ReturnRow')
class Returns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  TextColumn get returnNumber => text().unique()();
  RealColumn get totalAmount => real().withDefault(const Constant(0))();
  TextColumn get reason => text().nullable()();

  /// Who processed it, and who it was for, so a credit note can be traced.
  IntColumn get userId => integer().nullable().references(Users, #id)();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();

  /// How the money went back: cash, card, upi, or credit against the
  /// customer's account.
  TextColumn get refundMethod => text().withDefault(const Constant('cash'))();

  /// Tax reversed with the goods, kept split so the GST return balances.
  RealColumn get taxableTotal => real().withDefault(const Constant(0))();
  RealColumn get cgstTotal => real().withDefault(const Constant(0))();
  RealColumn get sgstTotal => real().withDefault(const Constant(0))();
  RealColumn get igstTotal => real().withDefault(const Constant(0))();

  /// An exchange is a return plus a fresh sale; this points at that sale so
  /// the pair can be read back together.
  IntColumn get exchangeSaleId => integer().nullable().references(Sales, #id)();
  DateTimeColumn get returnedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ReturnItemRow')
class ReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(Returns, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get refundAmount => real()();

  /// Copied from the original sale line so the credit note reprints correctly
  /// even after the product's price or tax rate has changed.
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get taxableValue => real().withDefault(const Constant(0))();
  RealColumn get taxAmount => real().withDefault(const Constant(0))();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  TextColumn get hsnCode => text().nullable()();
}

/// One cashier's session at the till, from opening float to closing count.
///
/// This is what makes the drawer auditable: without it there is no record of
/// who was on the counter when a shortfall appeared.
@DataClassName('ShiftRow')
class Shifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// Cash placed in the drawer at the start.
  RealColumn get openingFloat => real().withDefault(const Constant(0))();

  /// Cash physically counted at the end.
  RealColumn get closingCount => real().nullable()();

  /// Float plus cash sales less cash refunds and payouts, as the app computes
  /// it. Stored rather than recomputed so a closed shift never changes.
  RealColumn get expectedCash => real().nullable()();
  RealColumn get cashSales => real().withDefault(const Constant(0))();
  RealColumn get cardSales => real().withDefault(const Constant(0))();
  RealColumn get upiSales => real().withDefault(const Constant(0))();
  RealColumn get cashRefunds => real().withDefault(const Constant(0))();

  /// Money taken out of or put into the drawer mid-shift.
  RealColumn get paidIn => real().withDefault(const Constant(0))();
  RealColumn get paidOut => real().withDefault(const Constant(0))();
  IntColumn get saleCount => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

/// Cash added to or removed from the drawer during a shift, other than by a
/// sale — a supplier paid in cash, change fetched from the bank, and so on.
@DataClassName('CashMovementRow')
class CashMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shiftId =>
      integer().references(Shifts, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId => integer().nullable().references(Users, #id)();

  /// 'in' or 'out'.
  TextColumn get direction => text()();
  RealColumn get amount => real()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
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

/// Money settled with a customer or a supplier outside a sale or a delivery.
///
/// A credit sale grows a customer's balance and an unpaid delivery grows what
/// the shop owes; without this table neither could ever be brought back down.
@DataClassName('PartyPaymentRow')
class PartyPayments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'customer' for money taken in, 'supplier' for money paid out.
  TextColumn get partyType => text().withLength(min: 1, max: 16)();
  IntColumn get partyId => integer()();

  /// Voucher number, unique across both kinds so it can be quoted on paper.
  TextColumn get reference => text().unique()();
  RealColumn get amount => real()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Users,
    Roles,
    Permissions,
    RolePermissions,
    Categories,
    Brands,
    Units,
    ProductStyles,
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
    Shifts,
    CashMovements,
    PartyPayments,
    Expenses,
    ExpenseCategories,
    CashBook,
    BankBook,
    LedgerEntries,
    AuditLogs,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Runs the schema against a caller-supplied executor, so tests can drive the
  /// real migration and queries against an in-memory database.
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2 adds the style/size/colour matrix, HSN codes and the GST split.
        await m.createTable(productStyles);
        await m.addColumn(products, products.styleId);
        await m.addColumn(products, products.size);
        await m.addColumn(products, products.color);
        await m.addColumn(products, products.hsnCode);
        await m.addColumn(customers, customers.gstin);
        await m.addColumn(customers, customers.stateCode);
        await m.addColumn(sales, sales.upiAmount);
        await m.addColumn(sales, sales.cgstTotal);
        await m.addColumn(sales, sales.sgstTotal);
        await m.addColumn(sales, sales.igstTotal);
        await m.addColumn(sales, sales.placeOfSupply);
        await m.addColumn(sales, sales.customerGstin);
        await m.addColumn(saleItems, saleItems.hsnCode);
        await m.addColumn(saleItems, saleItems.taxRate);
        await m.addColumn(saleItems, saleItems.taxableValue);
        await m.addColumn(saleItems, saleItems.costPrice);
      }
      if (from < 3) {
        // v3 adds till sessions and turns returns into full credit notes.
        await m.createTable(shifts);
        await m.createTable(cashMovements);
        await m.addColumn(sales, sales.shiftId);
        await m.addColumn(returns, returns.userId);
        await m.addColumn(returns, returns.customerId);
        await m.addColumn(returns, returns.refundMethod);
        await m.addColumn(returns, returns.taxableTotal);
        await m.addColumn(returns, returns.cgstTotal);
        await m.addColumn(returns, returns.sgstTotal);
        await m.addColumn(returns, returns.igstTotal);
        await m.addColumn(returns, returns.exchangeSaleId);
        await m.addColumn(returnItems, returnItems.unitPrice);
        await m.addColumn(returnItems, returnItems.taxRate);
        await m.addColumn(returnItems, returnItems.taxableValue);
        await m.addColumn(returnItems, returnItems.taxAmount);
        await m.addColumn(returnItems, returnItems.costPrice);
        await m.addColumn(returnItems, returnItems.hsnCode);
      }
      if (from < 4) {
        // v4 lets money be settled against a customer or supplier balance.
        await m.createTable(partyPayments);
      }
    },
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

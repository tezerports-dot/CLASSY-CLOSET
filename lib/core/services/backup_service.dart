import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

/// What a backup or restore ended up doing.
class BackupResult {
  const BackupResult({
    required this.success,
    required this.message,
    this.path,
    this.fileCount = 0,
    this.bytes = 0,
  });

  final bool success;
  final String message;
  final String? path;
  final int fileCount;
  final int bytes;
}

/// Writes and reads the shop's whole data folder as a single zip.
///
/// A backup covers the SQLite file *and* the logo and product photos, because
/// a database restored without its images leaves every product blank. The zip
/// is a plain archive — it can be opened with Windows Explorer, which matters
/// when the person recovering the data is not the person who wrote this.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;
  Timer? _excelTimer;
  Timer? _zipTimer;
  Future<BackupResult>? _excelBackupInFlight;
  Future<BackupResult>? _zipBackupInFlight;

  static const _dbFileName = 'retailpro.sqlite';

  Future<Directory> automaticExcelDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(
      p.join(documents.path, 'Classy Closet Automatic Excel Backup'),
    );
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  Future<Directory> automaticZipDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(
      p.join(documents.path, 'Classy Closet Automatic Zip Backup'),
    );
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  void startAutomaticExcelBackup() {
    unawaited(writeAutomaticExcelBackup());
    unawaited(writeAutomaticZipBackup());
    _excelTimer?.cancel();
    _zipTimer?.cancel();
    _excelTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(writeAutomaticExcelBackup()),
    );
    _zipTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(writeAutomaticZipBackup()),
    );
  }

  Future<BackupResult> writeAutomaticExcelBackup() {
    final active = _excelBackupInFlight;
    if (active != null) return active;

    final backup = _writeAutomaticExcelBackup();
    _excelBackupInFlight = backup;
    backup.whenComplete(() {
      if (identical(_excelBackupInFlight, backup)) {
        _excelBackupInFlight = null;
      }
    });
    return backup;
  }

  Future<BackupResult> writeAutomaticZipBackup() {
    final active = _zipBackupInFlight;
    if (active != null) return active;

    final backup = _writeAutomaticZipBackup();
    _zipBackupInFlight = backup;
    backup.whenComplete(() {
      if (identical(_zipBackupInFlight, backup)) {
        _zipBackupInFlight = null;
      }
    });
    return backup;
  }

  Future<BackupResult> _writeAutomaticZipBackup() async {
    final folder = await automaticZipDirectory();
    final result = await backupTo(p.join(folder.path, suggestedFileName()));
    if (result.success) await _pruneAutomaticZipBackups(folder);
    return result;
  }

  Future<void> _pruneAutomaticZipBackups(Directory folder) async {
    final backups = folder
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('retailpro-backup-'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    for (final file in backups.skip(30)) {
      try {
        file.deleteSync();
      } on FileSystemException {
        // A locked old backup is harmless; try pruning again next time.
      }
    }
  }

  Future<BackupResult> _writeAutomaticExcelBackup() async {
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(PASSIVE)');
      final folder = await automaticExcelDirectory();
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Products');
      _writeProducts(excel['Products'], await _db.select(_db.products).get());
      _writeCustomers(
        excel['Customers'],
        await _db.select(_db.customers).get(),
      );
      _writeSuppliers(
        excel['Suppliers'],
        await _db.select(_db.suppliers).get(),
      );
      _writePurchases(
        excel['Purchases'],
        await _db.select(_db.purchases).get(),
      );
      _writeSales(excel['Sales'], await _db.select(_db.sales).get());

      final bytes = excel.save(fileName: 'classy-closet-live-backup.xlsx');
      if (bytes == null) {
        return const BackupResult(
          success: false,
          message: 'Could not create the Excel backup.',
        );
      }
      final target = File(
        p.join(folder.path, 'classy-closet-live-backup.xlsx'),
      );
      await target.writeAsBytes(bytes, flush: true);
      return BackupResult(
        success: true,
        message: 'Automatic Excel backup updated.',
        path: target.path,
        fileCount: 1,
        bytes: bytes.length,
      );
    } on Object catch (e) {
      return BackupResult(
        success: false,
        message: 'Automatic Excel backup failed: $e',
      );
    }
  }

  void _row(Sheet sheet, List<Object?> values) {
    sheet.appendRow([
      for (final value in values)
        if (value is num)
          DoubleCellValue(value.toDouble())
        else
          TextCellValue(value?.toString() ?? ''),
    ]);
  }

  void _writeProducts(Sheet sheet, List<ProductRow> rows) {
    _row(sheet, const [
      'ID',
      'SKU',
      'Barcode',
      'Name',
      'Size',
      'Colour',
      'Stock',
      'Purchase price',
      'Selling price',
      'Active',
    ]);
    for (final r in rows) {
      _row(sheet, [
        r.id,
        r.sku,
        r.barcode,
        r.name,
        r.size,
        r.color,
        r.currentStock < 0 ? 0 : r.currentStock,
        r.purchasePrice,
        r.sellingPrice,
        r.isActive ? 'Yes' : 'No',
      ]);
    }
  }

  void _writeCustomers(Sheet sheet, List<CustomerRow> rows) {
    _row(sheet, const ['ID', 'Name', 'Phone', 'Email', 'Balance']);
    for (final r in rows) {
      _row(sheet, [r.id, r.name, r.phone, r.email, r.currentBalance]);
    }
  }

  void _writeSuppliers(Sheet sheet, List<SupplierRow> rows) {
    _row(sheet, const ['ID', 'Name', 'Phone', 'Email', 'Balance']);
    for (final r in rows) {
      _row(sheet, [r.id, r.name, r.phone, r.email, r.currentBalance]);
    }
  }

  void _writePurchases(Sheet sheet, List<PurchaseRow> rows) {
    _row(sheet, const [
      'ID',
      'Supplier ID',
      'Invoice number',
      'Total',
      'Paid',
      'Outstanding',
      'Purchased at',
    ]);
    for (final r in rows) {
      _row(sheet, [
        r.id,
        r.supplierId,
        r.invoiceNumber,
        r.grandTotal,
        r.paidAmount,
        r.grandTotal - r.paidAmount,
        r.purchasedAt.toIso8601String(),
      ]);
    }
  }

  void _writeSales(Sheet sheet, List<SaleRow> rows) {
    _row(sheet, const [
      'ID',
      'Bill number',
      'Customer ID',
      'Total',
      'Paid',
      'Method',
      'Cash',
      'Card',
      'UPI',
      'Txn reference',
      'Sold at',
    ]);
    for (final r in rows) {
      _row(sheet, [
        r.id,
        r.receiptNumber,
        r.customerId,
        r.grandTotal,
        r.paidAmount,
        r.paymentMethod,
        r.cashAmount,
        r.cardAmount,
        r.upiAmount,
        r.paymentReference,
        r.soldAt.toIso8601String(),
      ]);
    }
  }

  Future<Directory> _dataDirectory() async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(p.join(support.path, 'ClassyCloset'));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  /// A filename that sorts by date and cannot collide within a minute.
  String suggestedFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'retailpro-backup-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.zip';
  }

  /// Copies everything into a zip at [targetPath].
  ///
  /// SQLite is checkpointed first so that anything still sitting in the
  /// write-ahead log is folded into the main file — without it a backup taken
  /// while the app is running can be missing the most recent sales.
  Future<BackupResult> backupTo(String targetPath) async {
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

      final source = await _dataDirectory();
      final archive = Archive();
      var count = 0;

      for (final entity in source.listSync(recursive: true)) {
        if (entity is! File) continue;
        final name = p.relative(entity.path, from: source.path);
        // The -wal and -shm files are rebuilt by SQLite on open and can
        // actively confuse a restore, so they are left out.
        if (name.endsWith('-wal') || name.endsWith('-shm')) continue;
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
        count++;
      }

      if (count == 0) {
        return const BackupResult(
          success: false,
          message: 'There is nothing to back up yet.',
        );
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        return const BackupResult(
          success: false,
          message: 'Could not compress the backup.',
        );
      }

      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(encoded, flush: true);

      return BackupResult(
        success: true,
        message: 'Backed up $count file(s).',
        path: targetPath,
        fileCount: count,
        bytes: encoded.length,
      );
    } on FileSystemException catch (e) {
      return BackupResult(
        success: false,
        message: 'Could not write the backup: ${e.message}',
      );
    }
  }

  /// Checks a zip really is one of our backups before anything is overwritten.
  Future<BackupResult> inspect(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final hasDb = archive.files.any((f) => p.basename(f.name) == _dbFileName);
      if (!hasDb) {
        return const BackupResult(
          success: false,
          message:
              'That zip does not contain a Classy Closet database, so it is '
              'not a backup of this app.',
        );
      }
      return BackupResult(
        success: true,
        message: 'Backup looks valid.',
        path: zipPath,
        fileCount: archive.files.length,
      );
    } catch (_) {
      return const BackupResult(
        success: false,
        message: 'That file could not be read as a zip.',
      );
    }
  }

  /// Replaces the live data folder with the contents of [zipPath].
  ///
  /// The current folder is copied aside first. A restore that fails halfway
  /// would otherwise leave the shop with neither the old data nor the new.
  /// The caller must restart the app afterwards: the database connection open
  /// right now still points at the file that was just replaced.
  Future<BackupResult> restoreFrom(String zipPath) async {
    final check = await inspect(zipPath);
    if (!check.success) return check;

    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final target = await _dataDirectory();

      final safetyCopy = Directory(
        '${target.path}-before-restore-'
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      if (target.existsSync()) {
        safetyCopy.createSync(recursive: true);
        for (final entity in target.listSync(recursive: true)) {
          if (entity is! File) continue;
          final name = p.relative(entity.path, from: target.path);
          final copy = File(p.join(safetyCopy.path, name));
          copy.parent.createSync(recursive: true);
          entity.copySync(copy.path);
        }
      }

      await _db.close();

      var written = 0;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final out = File(p.join(target.path, file.name));
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(file.content as List<int>, flush: true);
        written++;
      }

      return BackupResult(
        success: true,
        message:
            'Restored \$written file(s). Close and reopen Classy Closet to '
            'finish. Your previous data was kept at '
            '${p.basename(safetyCopy.path)}.',
        path: target.path,
        fileCount: written,
      );
    } on FileSystemException catch (e) {
      return BackupResult(
        success: false,
        message: 'Restore failed: ${e.message}',
      );
    }
  }
}

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/backup_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points path_provider at a scratch folder so the test never touches a real
/// installation's data.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  late Directory temp;
  late Directory dataDir;
  late AppDatabase db;
  late BackupService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('retailpro-backup-test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    dataDir = Directory(p.join(temp.path, 'ClassyCloset'))
      ..createSync(recursive: true);

    // Stand-ins for the real database and an uploaded product photo.
    File(
      p.join(dataDir.path, 'retailpro.sqlite'),
    ).writeAsStringSync('SQLite format 3 pretend database');
    Directory(p.join(dataDir.path, 'product_images')).createSync();
    File(
      p.join(dataDir.path, 'product_images', 'shirt.png'),
    ).writeAsStringSync('pretend image bytes');

    // A real in-memory database, so the WAL checkpoint the backup issues runs
    // for real rather than against a stub.
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    service = BackupService(db);
  });

  tearDown(() async {
    await db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('the suggested file name is dated and ends in .zip', () {
    final name = service.suggestedFileName();
    expect(name, startsWith('retailpro-backup-'));
    expect(name, endsWith('.zip'));
  });

  test('a backup contains the database and the product images', () async {
    final target = p.join(temp.path, 'out.zip');
    final result = await service.backupTo(target);

    expect(result.success, isTrue, reason: result.message);
    expect(File(target).existsSync(), isTrue);

    final archive = ZipDecoder().decodeBytes(File(target).readAsBytesSync());
    final names = archive.files.map((f) => f.name.replaceAll(r'\', '/'));
    expect(names, contains('retailpro.sqlite'));
    expect(names, contains('product_images/shirt.png'));
  });

  test('the write-ahead log side files are left out', () async {
    File(p.join(dataDir.path, 'retailpro.sqlite-wal')).writeAsStringSync('wal');
    File(p.join(dataDir.path, 'retailpro.sqlite-shm')).writeAsStringSync('shm');

    final target = p.join(temp.path, 'out.zip');
    await service.backupTo(target);

    final archive = ZipDecoder().decodeBytes(File(target).readAsBytesSync());
    final names = archive.files.map((f) => f.name);
    expect(names.any((n) => n.endsWith('-wal')), isFalse);
    expect(names.any((n) => n.endsWith('-shm')), isFalse);
  });

  test(
    'a zip without a database is rejected before anything is touched',
    () async {
      final bogus = p.join(temp.path, 'holiday-photos.zip');
      final archive = Archive()
        ..addFile(ArchiveFile('beach.jpg', 3, [1, 2, 3]));
      File(bogus).writeAsBytesSync(ZipEncoder().encode(archive)!);

      final result = await service.inspect(bogus);

      expect(result.success, isFalse);
      expect(result.message, contains('not a backup'));
    },
  );

  test('a file that is not a zip at all is rejected', () async {
    final notAZip = p.join(temp.path, 'notes.txt');
    File(notAZip).writeAsStringSync('just some text');

    final result = await service.inspect(notAZip);

    expect(result.success, isFalse);
  });

  test('restoring brings back data that was deleted afterwards', () async {
    final target = p.join(temp.path, 'out.zip');
    await service.backupTo(target);

    // Simulate the disaster the backup exists for.
    File(p.join(dataDir.path, 'retailpro.sqlite')).deleteSync();
    File(p.join(dataDir.path, 'product_images', 'shirt.png')).deleteSync();

    final result = await service.restoreFrom(target);

    expect(result.success, isTrue, reason: result.message);
    expect(
      File(p.join(dataDir.path, 'retailpro.sqlite')).readAsStringSync(),
      'SQLite format 3 pretend database',
    );
    expect(
      File(
        p.join(dataDir.path, 'product_images', 'shirt.png'),
      ).readAsStringSync(),
      'pretend image bytes',
    );
    expect(result.message, contains('reopen'));
  });

  test('restoring keeps a copy of what it replaced', () async {
    final target = p.join(temp.path, 'out.zip');
    await service.backupTo(target);

    File(
      p.join(dataDir.path, 'retailpro.sqlite'),
    ).writeAsStringSync('newer data that is about to be overwritten');

    await service.restoreFrom(target);

    final safetyCopies = temp
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).contains('before-restore'))
        .toList();
    expect(safetyCopies, hasLength(1));
    expect(
      File(
        p.join(safetyCopies.single.path, 'retailpro.sqlite'),
      ).readAsStringSync(),
      'newer data that is about to be overwritten',
    );
  });
}

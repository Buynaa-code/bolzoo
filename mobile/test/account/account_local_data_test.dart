import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/account_local_data.dart';
import 'package:hamtdaa/data/app_store.dart';
import 'package:hamtdaa/data/models.dart';

void main() {
  const a = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const b = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  late Directory sandbox;
  late Directory documents;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('hamtdaa-account-purge-');
    documents = await Directory('${sandbox.path}/documents').create();
  });
  tearDown(() => sandbox.delete(recursive: true));

  Future<File> photo(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString('photo');
  }

  Future<void> snapshot(String? id, List<String> photos) => FileAppStore(
    File('${documents.path}/${id == null ? '' : 'accounts/$id/'}hamtdaa.json'),
  ).write(
    AppData(
      profile: UserProfile(name: id ?? 'guest'),
      memories: [
        for (var i = 0; i < photos.length; i++)
          MemoryEntry(
            id: 'memory-$i',
            title: 'Memory $i',
            date: DateTime(2026, 9, 28),
            photoPath: photos[i],
          ),
      ],
    ),
  );

  Future<void> purge([String id = a]) =>
      AccountLocalData.purge(documentsDirectory: documents, userId: id);

  test('purges owned legacy and scoped files and is retry-idempotent', () async {
    final legacy = await photo('${documents.path}/memories_media/a.jpg');
    final scoped = await photo('${documents.path}/accounts/$a/memories_media/a.jpg');
    await snapshot(a, [legacy.path, scoped.path]);
    final receipt = await photo('${documents.path}/deletion-receipts/$a.json');

    await purge();
    expect(await legacy.exists(), isFalse);
    expect(await scoped.exists(), isFalse);
    expect(await Directory('${documents.path}/accounts/$a').exists(), isFalse);
    expect(await receipt.exists(), isTrue);
    await purge();
  });

  test('preserves gallery, guest and other account photos and snapshots', () async {
    final owned = await photo('${documents.path}/memories_media/owned.jpg');
    final shared = await photo('${documents.path}/memories_media/shared.jpg');
    final guest = await photo('${documents.path}/memories_media/guest.jpg');
    final original = await photo('${sandbox.path}/gallery.jpg');
    await snapshot(a, [owned.path, shared.path, guest.path, original.path]);
    await snapshot(b, [shared.path, '${documents.path}/memories_media/missing.jpg']);
    await snapshot(null, [guest.path]);
    final otherFile = File('${documents.path}/accounts/$b/hamtdaa.json');
    final originalOther = await otherFile.readAsBytes();

    await purge();
    expect(await owned.exists(), isFalse);
    for (final file in [shared, guest, original]) {
      expect(await file.exists(), isTrue);
    }
    expect(await otherFile.readAsBytes(), originalOther);
    expect(await File('${documents.path}/hamtdaa.json').exists(), isTrue);
  });

  test('malformed foreign snapshot fails before any photo removal', () async {
    final owned = await photo('${documents.path}/memories_media/owned.jpg');
    await snapshot(a, [owned.path]);
    await snapshot(b, []);
    await File('${documents.path}/accounts/$b/hamtdaa.json').writeAsString('{bad');
    await expectLater(purge(), throwsFormatException);
    expect(await owned.exists(), isTrue);
    expect(await File('${documents.path}/accounts/$a/hamtdaa.json').exists(), isTrue);
  });

  test('invalid account IDs never traverse into another directory', () async {
    await snapshot(a, []);
    for (final id in ['../$a', '$a/..', '', 'aaaaaaaa', '$a\n']) {
      await expectLater(purge(id), throwsArgumentError);
    }
    expect(await File('${documents.path}/accounts/$a/hamtdaa.json').exists(), isTrue);
  });

  test('foreign references into scoped directory fail closed', () async {
    final own = await photo('${documents.path}/accounts/$a/memories_media/a.jpg');
    await snapshot(a, [own.path]);
    await snapshot(b, [own.path]);
    await expectLater(purge(), throwsA(isA<FileSystemException>()));
    expect(await own.exists(), isTrue);
    expect(await File('${documents.path}/accounts/$a/hamtdaa.json').exists(), isTrue);
  });

  test('symlinked account or snapshot fails without following target', () async {
    final elsewhere = await Directory('${sandbox.path}/elsewhere').create();
    final original = await photo('${elsewhere.path}/hamtdaa.json');
    await Directory('${documents.path}/accounts').create();
    final alias = await Link('${documents.path}/accounts/$a').create(elsewhere.path);
    await expectLater(purge(), throwsA(isA<FileSystemException>()));
    expect(await original.exists(), isTrue);
    await alias.delete();
    await Directory(alias.path).create();
    await Link('${alias.path}/hamtdaa.json').create(original.path);
    await expectLater(purge(), throwsA(isA<FileSystemException>()));
    expect(await original.readAsString(), 'photo');
  }, skip: Platform.isWindows);

  test('nested account links are unlinked without removing their targets', () async {
    final original = await photo('${sandbox.path}/gallery.jpg');
    await snapshot(a, [original.path]);
    await Link('${documents.path}/accounts/$a/alias').create(sandbox.path);
    await purge();
    expect(await original.readAsString(), 'photo');
    expect(await Directory('${documents.path}/accounts/$a').exists(), isFalse);
  }, skip: Platform.isWindows);

  test('legacy symlinks and redirected media do not delete originals', () async {
    final original = await photo('${sandbox.path}/gallery.jpg');
    final media = await Directory('${documents.path}/memories_media').create();
    final alias = await Link('${media.path}/alias.jpg').create(original.path);
    await snapshot(a, [alias.path]);
    await purge();
    expect(await original.exists(), isTrue);
    expect(await alias.exists(), isTrue);

    await alias.delete();
    await media.delete();
    await Link(media.path).create(sandbox.path);
    await snapshot(a, ['${media.path}/gallery.jpg']);
    await purge();
    expect(await original.exists(), isTrue);
  }, skip: Platform.isWindows);

  test('an alias from another account protects a legacy photo', () async {
    final owned = await photo('${documents.path}/memories_media/owned.jpg');
    final alias = await Link('${sandbox.path}/foreign-alias').create(owned.path);
    await snapshot(a, [owned.path]);
    await snapshot(b, [alias.path]);
    await purge();
    expect(await owned.exists(), isTrue);
    expect(await alias.exists(), isTrue);
  }, skip: Platform.isWindows);
}

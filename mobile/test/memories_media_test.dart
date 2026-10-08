import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/features/memories/media_files.dart';

void main() {
  late Directory sandbox;
  late Directory documents;
  late Directory managed;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('hamtdaa-media-test-');
    documents = await Directory('${sandbox.path}/documents').create();
    managed = await Directory('${documents.path}/memories_media').create();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<File> image(String path) => File(path).writeAsString('test image');

  test('removes an unreferenced managed photo after a commit', () async {
    final photo = await image('${managed.path}/old.jpg');

    expect(
      await deleteUnusedManagedPhoto(
        photo.path,
        referencedPaths: () => const [],
        documentsDirectory: documents,
      ),
      isTrue,
    );
    expect(await photo.exists(), isFalse);
  });

  test('account cleanup is confined to that account photo directory', () async {
    final accountA = await Directory(
      '${documents.path}/accounts/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/memories_media',
    ).create(recursive: true);
    final accountB = await Directory(
      '${documents.path}/accounts/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/memories_media',
    ).create(recursive: true);
    final own = await image('${accountA.path}/same-name.jpg');
    final other = await image('${accountB.path}/same-name.jpg');
    final local = await image('${managed.path}/same-name.jpg');

    for (final path in [other.path, local.path]) {
      expect(
        await deleteUnusedManagedPhoto(
          path,
          referencedPaths: () => const [],
          documentsDirectory: accountA.parent,
        ),
        isFalse,
      );
      expect(await File(path).exists(), isTrue);
    }
    expect(
      await deleteUnusedManagedPhoto(
        own.path,
        referencedPaths: () => const [],
        documentsDirectory: accountA.parent,
      ),
      isTrue,
    );
    expect(await own.exists(), isFalse);
    expect(await other.exists(), isTrue);
    expect(await local.exists(), isTrue);
  });

  test('preserves a photo still used by a remaining memory', () async {
    final photo = await image('${managed.path}/shared.jpg');

    expect(
      await deleteUnusedManagedPhoto(
        photo.path,
        referencedPaths: () => [null, photo.path],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await photo.exists(), isTrue);
  });

  test('never removes a gallery original or a similarly named sibling', () async {
    final gallery = await image('${sandbox.path}/gallery.jpg');
    final siblingDirectory =
        await Directory('${documents.path}/memories_media_old').create();
    final sibling = await image('${siblingDirectory.path}/photo.jpg');

    for (final photo in [gallery, sibling]) {
      expect(
        await deleteUnusedManagedPhoto(
          photo.path,
          referencedPaths: () => const [],
          documentsDirectory: documents,
        ),
        isFalse,
      );
      expect(await photo.exists(), isTrue);
    }
  });

  test('rejects dot-segment traversal outside managed photos', () async {
    final original = await image('${documents.path}/original.jpg');

    expect(
      await deleteUnusedManagedPhoto(
        '${managed.path}/../original.jpg',
        referencedPaths: () => const [],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await original.exists(), isTrue);
  });

  test('preserves a managed photo referenced through a symlink alias', () async {
    final photo = await image('${managed.path}/shared.jpg');
    final alias = await Link('${sandbox.path}/alias.jpg').create(photo.path);

    expect(
      await deleteUnusedManagedPhoto(
        photo.path,
        referencedPaths: () => [alias.path],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await photo.exists(), isTrue);
  }, skip: Platform.isWindows);

  test('rejects a managed symlink that targets a gallery original', () async {
    final original = await image('${sandbox.path}/original.jpg');
    final alias = await Link('${managed.path}/photo.jpg').create(original.path);

    expect(
      await deleteUnusedManagedPhoto(
        alias.path,
        referencedPaths: () => const [],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await original.exists(), isTrue);
    expect(await alias.exists(), isTrue);
  }, skip: Platform.isWindows);

  test('rejects a media directory redirected outside documents', () async {
    await managed.delete();
    final elsewhere = await Directory('${sandbox.path}/elsewhere').create();
    final original = await image('${elsewhere.path}/original.jpg');
    await Link(managed.path).create(elsewhere.path);

    expect(
      await deleteUnusedManagedPhoto(
        '${managed.path}/original.jpg',
        referencedPaths: () => const [],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await original.exists(), isTrue);
  }, skip: Platform.isWindows);

  test('rechecks current references before removing a file', () async {
    final photo = await image('${managed.path}/newly-referenced.jpg');
    var reads = 0;

    expect(
      await deleteUnusedManagedPhoto(
        photo.path,
        referencedPaths: () => ++reads == 1 ? const [] : [photo.path],
        documentsDirectory: documents,
      ),
      isFalse,
    );
    expect(await photo.exists(), isTrue);
  });

  test('null, missing and directory paths safely skip cleanup', () async {
    for (final path in [null, '${managed.path}/missing.jpg', managed.path]) {
      expect(
        await deleteUnusedManagedPhoto(
          path,
          referencedPaths: () => const [],
          documentsDirectory: documents,
        ),
        isFalse,
      );
    }
    expect(await managed.exists(), isTrue);
  });
}

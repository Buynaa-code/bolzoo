import 'dart:io';

import '../data/app_store.dart';
import '../features/memories/media_files.dart';

/// Removes one account's local copies after its mutations have been drained.
///
/// The caller keeps its deletion receipt outside the account directory until
/// this finishes. Errors deliberately propagate so cleanup can be retried.
class AccountLocalData {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Future<void> purge({
    required Directory documentsDirectory,
    required String userId,
  }) async {
    if (!_uuid.hasMatch(userId)) {
      throw ArgumentError.value(userId, 'userId', 'Expected an account UUID.');
    }
    final documents = Directory(
      await documentsDirectory.resolveSymbolicLinks(),
    );
    final suppliedDocumentsPath = _absolute(documentsDirectory.path);
    String accountPath(String value) {
      final path = _absolute(value);
      return _inside(path, suppliedDocumentsPath)
          ? '${documents.path}${path.substring(suppliedDocumentsPath.length)}'
          : path;
    }
    final accounts = Directory('${documents.path}/accounts');
    if (!await _directoryExistsSafely(accounts)) return;
    final own = Directory('${accounts.path}/$userId');
    if (!await _directoryExistsSafely(own)) return;

    // Resolve every snapshot before removing anything. An unreadable other
    // account must never be mistaken for an account without photo references.
    final ownedPhotos = await _photos(File('${own.path}/hamtdaa.json'));
    final referenced = await _photos(File('${documents.path}/hamtdaa.json'));
    await for (final entry in accounts.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (name == userId || !_uuid.hasMatch(name)) continue;
      final other = Directory(entry.path);
      if (!await _directoryExistsSafely(other)) continue;
      referenced.addAll(await _photos(File('${other.path}/hamtdaa.json')));
    }

    final references = <String>{};
    for (final path in referenced) {
      references.add(accountPath(path));
      final type = await FileSystemEntity.type(path);
      if (type != FileSystemEntityType.notFound) {
        references.add(await File(path).resolveSymbolicLinks());
      }
    }
    // This should not occur in normal account-scoped storage. Fail closed if a
    // legacy or manually imported snapshot still points into this account.
    if (references.any((path) => _inside(path, own.path))) {
      throw FileSystemException(
        'Another local account still references this account directory.',
        own.path,
      );
    }

    final legacy = Directory('${documents.path}/memories_media');
    for (final rawPath in ownedPhotos.toSet()) {
      final path = accountPath(rawPath);
      if (!_inside(path, legacy.path) || references.contains(path)) continue;
      // Originals, aliases and redirected media directories are not app-owned
      // copies. Never follow a symlink to delete its target.
      if (await FileSystemEntity.type(legacy.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await legacy.resolveSymbolicLinks() != legacy.path ||
          await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      final canonical = await File(path).resolveSymbolicLinks();
      if (!_inside(canonical, legacy.path) || references.contains(canonical)) {
        continue;
      }
      // Missing references are irrelevant to cleanup; passing them to the
      // defensive helper would make its alias resolution fail closed forever.
      final liveReferences = <String>[];
      for (final reference in references) {
        if (await FileSystemEntity.type(reference) !=
            FileSystemEntityType.notFound) {
          liveReferences.add(reference);
        }
      }
      final removed = await deleteUnusedManagedPhoto(
        path,
        referencedPaths: () => liveReferences,
        documentsDirectory: documents,
      );
      if (!removed && await FileSystemEntity.type(path) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('Could not remove an account photo.', path);
      }
    }

    // Dart's recursive deletion unlinks nested symlinks, without following
    // their targets. Recheck the root so a redirected account is never erased.
    if (await _directoryExistsSafely(own)) await own.delete(recursive: true);
  }

  static Future<bool> _directoryExistsSafely(Directory directory) async {
    final type = await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != directory.path) {
      throw FileSystemException('Unsafe account directory.', directory.path);
    }
    return true;
  }

  static Future<List<String>> _photos(File snapshot) async {
    final type = await FileSystemEntity.type(snapshot.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return [];
    if (type != FileSystemEntityType.file) {
      throw FileSystemException('Unsafe account snapshot.', snapshot.path);
    }
    final data = await FileAppStore(snapshot).read();
    return data.memories.map((m) => m.photoPath).whereType<String>().toList();
  }

  static String _absolute(String path) =>
      Uri.file(File(path).absolute.path).normalizePath().toFilePath();

  static bool _inside(String child, String parent) =>
      child.startsWith('$parent${Platform.pathSeparator}');
}

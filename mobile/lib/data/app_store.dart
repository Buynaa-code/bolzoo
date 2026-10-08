import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract interface class AppStore {
  Future<AppData> read();
  Future<void> write(AppData data);
}

abstract interface class FileBackedAppStore implements AppStore {
  Directory get directory;
}

/// Stores one atomic snapshot. A malformed existing file is never reset.
class FileAppStore implements FileBackedAppStore {
  FileAppStore(this.file);

  final File file;
  @override
  Directory get directory => file.parent;

  @override
  Future<AppData> read() async {
    if (!await file.exists()) {
      // An existing directory or link error must not masquerade as a fresh app.
      final type = await FileSystemEntity.type(file.path);
      if (type != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'App data path is not a readable file.',
          file.path,
        );
      }
      return AppData();
    }
    final contents = await file.readAsString();
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException(
        'Saved app data could not be read. The original file has been preserved.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved app data must be a JSON object.');
    }
    final stored = AppData.fromJson(decoded);
    return stored.copyWith(
      memories: stored.memories
          .map(
            (memory) =>
                memory.copyWith(photoPath: _resolvePhotoPath(memory.photoPath)),
          )
          .toList(),
    );
  }

  @override
  Future<void> write(AppData data) async {
    // Serialize before touching disk so encoding errors leave the old file intact.
    final stored = data.copyWith(
      memories: data.memories
          .map(
            (memory) =>
                memory.copyWith(photoPath: _encodePhotoPath(memory.photoPath)),
          )
          .toList(),
    );
    final contents = jsonEncode(stored.toJson());
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${newLocalId()}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      // Same-directory rename replaces the previous complete snapshot atomically.
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Uri get _documentsUri => file.parent.absolute.uri.normalizePath();

  String? _encodePhotoPath(String? path) {
    if (path == null) return null;
    if (!File(path).isAbsolute) {
      throw const FormatException(
        'Photo paths in app state must be resolved absolute paths.',
      );
    }
    final managedPrefix = _documentsUri.resolve('memories_media/').toFilePath();
    if (!path.startsWith(managedPrefix)) {
      // Older snapshots and externally supplied paths retain their exact value.
      return path;
    }
    final suffix = path
        .substring(managedPrefix.length)
        .replaceAll(Platform.pathSeparator, '/');
    final relative = 'memories_media/$suffix';
    _validateManagedRelativePath(relative);
    return relative;
  }

  String? _resolvePhotoPath(String? path) {
    if (path == null || File(path).isAbsolute) return path;
    _validateManagedRelativePath(path);
    // Treat this as a filesystem path, never as a URL to be percent-decoded.
    return File(
      '${_documentsUri.toFilePath()}'
      '${path.replaceAll('/', Platform.pathSeparator)}',
    ).path;
  }

  void _validateManagedRelativePath(String path) {
    final segments = path.split('/');
    if (!path.startsWith('memories_media/') ||
        segments.length < 2 ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) ||
        RegExp(r'[%\\:\x00]').hasMatch(path)) {
      throw const FormatException(
        'Invalid managed photo path in saved app data.',
      );
    }
  }
}

/// An explicit in-memory store for tests and previews, never a disk fallback.
class MemoryAppStore implements AppStore {
  MemoryAppStore([AppData? initialData]) : _data = initialData ?? AppData();

  AppData _data;

  @override
  Future<AppData> read() async => _data;

  @override
  Future<void> write(AppData data) async {
    _data = data;
  }
}

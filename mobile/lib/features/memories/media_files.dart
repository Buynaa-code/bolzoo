import 'dart:io';

import 'package:path_provider/path_provider.dart';

String _absolutePath(String path) =>
    Uri.file(File(path).absolute.path).normalizePath().toFilePath();

bool _isInside(String child, String parent) =>
    child.startsWith('$parent${Platform.pathSeparator}');

/// Removes an unused app-owned copy after its record was successfully committed.
///
/// Both the supplied path and its resolved target must remain under the app's
/// memories_media directory. Gallery originals, directory symlinks that escape
/// that directory, and files still referenced by another record are preserved.
/// [referencedPaths] is evaluated during cleanup so callers provide live data.
/// Any uncertainty or filesystem error keeps the file and returns false.
Future<bool> deleteUnusedManagedPhoto(
  String? photoPath, {
  required Iterable<String?> Function() referencedPaths,
  Directory? documentsDirectory,
}) async {
  if (photoPath == null || photoPath.trim().isEmpty) return false;
  try {
    final documents =
        documentsDirectory ?? await getApplicationDocumentsDirectory();
    final managed = Directory('${documents.path}/memories_media');
    final suppliedPath = _absolutePath(photoPath);
    final managedPath = _absolutePath(managed.path);
    if (!_isInside(suppliedPath, managedPath)) return false;

    final canonicalDocuments = await documents.resolveSymbolicLinks();
    final canonicalManaged = await managed.resolveSymbolicLinks();
    if (canonicalManaged !=
        '$canonicalDocuments${Platform.pathSeparator}memories_media') {
      return false;
    }

    final candidate = File(suppliedPath);
    final canonicalCandidate = await candidate.resolveSymbolicLinks();
    if (!_isInside(canonicalCandidate, canonicalManaged)) return false;

    for (final reference in referencedPaths()) {
      if (reference == null || reference.trim().isEmpty) continue;
      if (_absolutePath(reference) == suppliedPath) return false;
      if (await File(reference).resolveSymbolicLinks() == canonicalCandidate) {
        return false;
      }
    }

    // Read references once more after the awaited filesystem operations. Exact
    // and normalized aliases cover newly written records in this app, which
    // stores managed absolute paths rather than symlink aliases.
    if (referencedPaths().whereType<String>().any(
      (reference) => reference.trim().isNotEmpty &&
          (_absolutePath(reference) == suppliedPath ||
              _absolutePath(reference) == canonicalCandidate),
    )) {
      return false;
    }
    await candidate.delete();
    return true;
  } catch (_) {
    // Cleanup is best effort; it must never turn a committed save into failure.
    return false;
  }
}

import 'dart:io';

import '../auth/auth_models.dart';
import 'app_store.dart';
import 'models.dart';

/// Gives each signed-in account a separate local snapshot namespace.
///
/// Guest data is intentionally not imported here. Import is an explicit,
/// user-confirmed operation with its own mapping and retry rules.
class AccountScopedFileStore implements FileBackedAppStore {
  AccountScopedFileStore({required Directory documentsDirectory, required this.scope})
    : _delegate = FileAppStore(
        File(
          '${documentsDirectory.path}/accounts/${_safeId(scope.userId)}/hamtdaa.json',
        ),
      );

  final AccountScope scope;
  final FileAppStore _delegate;
  @override
  Directory get directory => _delegate.directory;

  @override
  Future<AppData> read() => _delegate.read();

  @override
  Future<void> write(AppData data) => _delegate.write(data);
}

String _safeId(String id) {
  if (!RegExp(r'^[0-9a-fA-F-]{8,80}$').hasMatch(id)) {
    throw ArgumentError('Account ID is not a valid UUID-like value.');
  }
  return id;
}

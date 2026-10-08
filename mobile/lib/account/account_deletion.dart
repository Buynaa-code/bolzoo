import 'dart:io';
import 'account_local_data.dart';
import 'account_repository.dart';

class AccountDeletionPending implements Exception {
  const AccountDeletionPending();
}

/// A durable record of the user's explicit deletion confirmation. No tokens,
/// email addresses, or content are saved in this journal.
class AccountDeletionCoordinator {
  AccountDeletionCoordinator(this.documentsDirectory);
  final Directory documentsDirectory;
  Future<void>? _operation;
  AccountRepository? _operationRepository;

  File _marker(String userId) {
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(userId)) throw ArgumentError('Invalid account ID');
    return File('${documentsDirectory.path}/account_deletions/$userId.pending');
  }

  Future<bool> pending(String userId) => _marker(userId).exists();

  Future<void> markPending(String userId) async {
    final marker = _marker(userId);
    await marker.parent.create(recursive: true);
    await marker.writeAsString('confirmed\n', flush: true);
  }

  /// Also clears confirmed local deletion work after an app restart even when
  /// the old Auth session has expired. Remote work still requires that account.
  Future<void> purgePendingLocal() async {
    final directory = Directory('${documentsDirectory.path}/account_deletions');
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.pending')) continue;
      final name = entry.uri.pathSegments.last;
      final userId = name.substring(0, name.length - '.pending'.length);
      _marker(userId);
      await AccountLocalData.purge(documentsDirectory: documentsDirectory, userId: userId);
    }
  }

  Future<void> delete({
    required AccountRepository repository,
    required Future<void> Function() freeze,
    required Future<void> Function() clearReminders,
    required Future<void> Function() signOut,
  }) {
    if (_operation != null) {
      final active = _operationRepository!;
      if (active.userId != repository.userId || !active.sessionCurrent || !repository.sessionCurrent) {
        throw const AccountOperationException('session_changed');
      }
      return _operation!;
    }
    final result = _delete(repository, freeze, clearReminders, signOut);
    _operation = result;
    _operationRepository = repository;
    return result.whenComplete(() { _operation = null; _operationRepository = null; });
  }

  Future<void> _delete(AccountRepository repository,
      Future<void> Function() freeze,
      Future<void> Function() clearReminders,
      Future<void> Function() signOut) async {
    if (!repository.sessionCurrent) {
      throw const AccountOperationException('session_changed');
    }
    await markPending(repository.userId);
    await freeze();
    // The user has confirmed permanent deletion. Clear local content before
    // remote work, so a network failure / expired session cannot retain it.
    await AccountLocalData.purge(
      documentsDirectory: documentsDirectory, userId: repository.userId,
    );
    if (!repository.sessionCurrent) {
      throw const AccountOperationException('session_changed');
    }
    await clearReminders();
    await repository.deleteAccount();
    if (!repository.sessionCurrent) {
      throw const AccountOperationException('session_changed');
    }
    await signOut();
    final marker = _marker(repository.userId);
    if (await marker.exists()) await marker.delete();
  }
}

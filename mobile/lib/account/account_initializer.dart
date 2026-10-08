import 'account_deletion.dart';
import 'account_repository.dart';

/// Guard each asynchronous boundary before journaling or erasing local data.
Future<void> initializeAccountAccess({
  required String userId,
  required bool Function() sessionCurrent,
  required Future<bool> Function() pending,
  required Future<Map<String, dynamic>> Function() status,
  required Future<void> Function() markPending,
  required Future<void> Function() purgeLocal,
  required Future<void> Function() bootstrap,
}) async {
  void check() {
    if (!sessionCurrent()) throw const AccountOperationException('session_changed');
  }
  check();
  final isPending = await pending();
  check();
  if (isPending) throw const AccountDeletionPending();
  final response = await status();
  check();
  if (response['ok'] != true || response['userId'] != userId ||
      !const {'active', 'deleting'}.contains(response['state'])) {
    throw const AccountOperationException('invalid_status');
  }
  if (response['state'] == 'deleting') {
    await markPending(); check();
    await purgeLocal(); check();
    throw const AccountDeletionPending();
  }
  await bootstrap(); check();
}

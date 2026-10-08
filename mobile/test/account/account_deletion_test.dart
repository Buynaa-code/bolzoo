import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/account/account_deletion.dart';
import 'package:hamtdaa/account/account_repository.dart';
import 'package:hamtdaa/data/account_scoped_store.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/data/app_controller.dart';

const user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
class _Repository implements AccountRepository {
  int calls = 0;
  bool fail = false;
  Completer<void>? barrier;
  @override String get userId => user;
  @override bool sessionCurrent = true;
  @override Future<void> deleteAccount() async {
    calls++;
    if (barrier != null) await barrier!.future;
    if (fail) throw const AccountOperationException('network');
  }
  @override Future<Map<String,dynamic>> exportData() => throw UnimplementedError();
  @override Future<Uint8List> downloadMedia(String key) => throw UnimplementedError();
}

class _BlockedStore implements AppStore {
  AppData snapshot = AppData();
  final began = Completer<void>(), finish = Completer<void>();
  @override Future<AppData> read() async => snapshot;
  @override Future<void> write(AppData data) async {
    began.complete(); await finish.future; snapshot = data;
  }
}

void main() {
  late Directory docs;
  setUp(() async { docs = await Directory.systemTemp.createTemp('hamtdaa-delete-test-'); });
  tearDown(() async { await docs.delete(recursive: true); });

  test('confirmed remote failure removes local data, journals and resumes once', () async {
    final store = AccountScopedFileStore(documentsDirectory: docs,
      scope: const AccountScope(userId: user, epoch: 1));
    final controller = AppController(store);
    await controller.load();
    await controller.updateProfile(const UserProfile(name:'Own private'));
    final repository = _Repository()..fail = true;
    final coordinator = AccountDeletionCoordinator(docs);
    var reminders = 0, signouts = 0;
    Future<void> delete() => coordinator.delete(repository: repository,
      freeze: controller.freezeForAccountDeletion,
      clearReminders: () async { reminders++; }, signOut: () async {signouts++;});
    await expectLater(delete(), throwsA(isA<AccountOperationException>()));
    expect(await coordinator.pending(user), isTrue);
    expect(await store.directory.exists(), isFalse);
    expect(controller.data.profile.name, isEmpty);
    expect(signouts, 0);
    repository..fail = false..barrier = Completer<void>();
    final first = delete(); final second = delete();
    await Future<void>.delayed(const Duration(milliseconds:30));
    expect(repository.calls, 2);
    repository.barrier!.complete();
    await Future.wait([first, second]);
    expect(signouts, 1); expect(reminders, 2);
    expect(await coordinator.pending(user), isFalse);
    controller.dispose();
  });

  test('freeze waits for a pending write, rejects queued and future mutations', () async {
    final store = _BlockedStore();
    final controller = AppController(store);
    await controller.load();
    final save = controller.updateProfile(const UserProfile(name: 'Before'));
    await store.began.future;
    final freeze = controller.freezeForAccountDeletion();
    final after = controller.updateProfile(const UserProfile(name: 'Too late'));
    final rejected = expectLater(after, throwsStateError);
    var frozen = false; freeze.then((_) => frozen = true);
    await Future<void>.delayed(Duration.zero);
    expect(frozen, isFalse);
    store.finish.complete();
    await save; await freeze; await rejected;
    expect(store.snapshot.profile.name, 'Before');
    expect(controller.data.profile.name, isEmpty);
    await expectLater(controller.exportOwnSnapshot(), throwsStateError);
    controller.dispose();
  });

  test('cold start cleans only previously confirmed account namespace', () async {
    final store = AccountScopedFileStore(documentsDirectory: docs,
      scope: const AccountScope(userId:user,epoch:1));
    await store.write(AppData(profile: const UserProfile(name:'Own')));
    final guest = File('${docs.path}/hamtdaa.json');
    await FileAppStore(guest).write(AppData(profile:const UserProfile(name:'Guest')));
    final coordinator = AccountDeletionCoordinator(docs);
    await coordinator.markPending(user);
    await AccountDeletionCoordinator(docs).purgePendingLocal();
    expect(await store.directory.exists(), isFalse);
    expect(await guest.exists(), isTrue);
    expect(await coordinator.pending(user), isTrue);
  });

  test('changed session never begins destructive local work', () async {
    final coordinator = AccountDeletionCoordinator(docs);
    var frozen = false;
    await expectLater(coordinator.delete(repository:_Repository()..sessionCurrent=false,
      freeze: () async { frozen=true; }, clearReminders:() async {}, signOut: () async {}),
      throwsA(isA<AccountOperationException>()));
    expect(frozen,isFalse); expect(await coordinator.pending(user),isFalse);
  });
}

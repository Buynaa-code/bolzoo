import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/data/account_scoped_store.dart';
import 'package:hamtdaa/data/models.dart';

void main() {
  test('accounts receive separate local snapshots', () async {
    final directory = await Directory.systemTemp.createTemp('hamtdaa-scope-');
    addTearDown(() => directory.delete(recursive: true));
    const a = AccountScope(
      userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      epoch: 1,
    );
    const b = AccountScope(
      userId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      epoch: 1,
    );
    final aStore = AccountScopedFileStore(documentsDirectory: directory, scope: a);
    final bStore = AccountScopedFileStore(documentsDirectory: directory, scope: b);
    await aStore.write(
      AppData(profile: const UserProfile(name: 'А')),
    );
    expect((await bStore.read()).profile.name, isEmpty);
    expect((await aStore.read()).profile.name, 'А');
  });

  test('guest-like or path-shaped IDs are rejected', () async {
    final directory = await Directory.systemTemp.createTemp('hamtdaa-scope-');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      () => AccountScopedFileStore(
        documentsDirectory: directory,
        scope: const AccountScope(userId: '../guest', epoch: 1),
      ),
      throwsArgumentError,
    );
  });
}

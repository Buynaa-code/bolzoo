import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/secure_auth_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemorySecureStore extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<void>? writeGate;
  @override
  Future<String?> read({required String key, IOSOptions? iOptions,
    AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions,
    MacOsOptions? mOptions, WindowsOptions? wOptions}) async => values[key];
  @override
  Future<void> write({required String key, required String? value,
    IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
    WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    await writeGate?.future;
    if (failWrite) throw StateError('unavailable');
    if (value != null) values[key] = value;
  }
  @override
  Future<void> delete({required String key, IOSOptions? iOptions,
    AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions,
    MacOsOptions? mOptions, WindowsOptions? wOptions}) async { values.remove(key); }
}

class MemoryLegacyStore extends LocalStorage {
  String? value;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<void> persistSession(String persistSessionString) async { value = persistSessionString; }
  @override
  Future<void> removePersistedSession() async { value = null; }
}

void main() {
  test('migration deletes plaintext only after a successful secure write', () async {
    final secure = MemorySecureStore()..failWrite = true;
    final legacy = MemoryLegacyStore()..value = 'test-session';
    final store = SecureAuthStorage(supabaseUrl: 'https://one.supabase.co',
      storage: secure, legacyStorage: legacy);
    await expectLater(store.initialize(), throwsStateError);
    expect(legacy.value, 'test-session');
    secure.failWrite = false;
    await store.initialize();
    expect(legacy.value, isNull);
    expect(await store.accessToken(), 'test-session');
  });
  test('project isolation and logout cannot be overtaken by an earlier write', () async {
    final secure = MemorySecureStore();
    final one = SecureAuthStorage(supabaseUrl: 'https://one.supabase.co',
      storage: secure, legacyStorage: MemoryLegacyStore());
    final two = SecureAuthStorage(supabaseUrl: 'https://two.supabase.co',
      storage: secure, legacyStorage: MemoryLegacyStore());
    await one.initialize();
    await two.initialize();
    await two.persistSession('second-account');
    secure.writeGate = Completer<void>();
    final refresh = one.persistSession('old-refresh');
    final logout = one.removePersistedSession();
    secure.writeGate!.complete();
    await Future.wait([refresh, logout]);
    expect(await one.hasAccessToken(), isFalse);
    expect(await two.accessToken(), 'second-account');
  });
}

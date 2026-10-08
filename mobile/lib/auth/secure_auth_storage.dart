import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Project-scoped session storage. Auth tokens never enter the app JSON store.
class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage({
    required String supabaseUrl,
    FlutterSecureStorage? storage,
    LocalStorage? legacyStorage,
  }) : _key = 'hamtdaa.auth.${Uri.parse(supabaseUrl).host}',
       _storage = storage ?? const FlutterSecureStorage(
         iOptions: IOSOptions(
           accessibility: KeychainAccessibility.unlocked_this_device,
         ),
         mOptions: MacOsOptions(usesDataProtectionKeychain: false),
       ),
       _legacy = legacyStorage ?? SharedPreferencesLocalStorage(
         persistSessionKey:
             'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
       );

  final String _key;
  final FlutterSecureStorage _storage;
  final LocalStorage _legacy;
  Future<void> _pending = Future<void>.value();

  // SDK auth callbacks may overlap. A sign-out delete must follow any preceding
  // token refresh write, so an old callback cannot resurrect a stored session.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<void> initialize() => _serial(() async {
    await _legacy.initialize();
    final current = await _storage.read(key: _key);
    final old = await _legacy.accessToken();
    if (current == null && old != null) {
      // Keep the previous value until the secure write succeeds.
      await _storage.write(key: _key, value: old);
    }
    await _legacy.removePersistedSession();
  });

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() =>
      _serial(() => _storage.read(key: _key));

  @override
  Future<void> persistSession(String persistSessionString) =>
      _serial(() => _storage.write(key: _key, value: persistSessionString));

  @override
  Future<void> removePersistedSession() => _serial(() async {
    await _storage.delete(key: _key);
    await _legacy.removePersistedSession();
  });
}

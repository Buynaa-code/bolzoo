import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CloudflareSessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// A separate origin-scoped key prevents staging auth from reusing or replacing
/// production Supabase sessions. Credentials never enter app content files.
class SecureCloudflareSessionStorage implements CloudflareSessionStorage {
  SecureCloudflareSessionStorage(Uri origin, {FlutterSecureStorage? storage})
    : _key = 'hamtdaa.cloudflare.auth.${origin.origin}',
      _storage = storage ?? const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
        mOptions: MacOsOptions(usesDataProtectionKeychain: false),
      );

  final String _key;
  final FlutterSecureStorage _storage;
  Future<void> _pending = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<String?> read() => _serial(() => _storage.read(key: _key));
  @override
  Future<void> write(String value) =>
      _serial(() => _storage.write(key: _key, value: value));
  @override
  Future<void> clear() => _serial(() => _storage.delete(key: _key));
}

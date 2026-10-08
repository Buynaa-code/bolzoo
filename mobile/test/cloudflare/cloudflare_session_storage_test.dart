import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';

class _SecureStore extends FlutterSecureStorage {
  final values = <String, String>{};
  Completer<void>? writeGate;

  @override
  Future<String?> read({
    required String key, AppleOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key, required String? value, AppleOptions? iOptions,
    AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions,
    AppleOptions? mOptions, WindowsOptions? wOptions,
  }) async {
    await writeGate?.future;
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key, AppleOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

void main() {
  test('native storage isolates Cloudflare origins and existing auth keys', () async {
    final secure = _SecureStore();
    secure.values['hamtdaa.auth.production'] = 'existing-session';
    final first = SecureCloudflareSessionStorage(Uri.parse('https://one.example'), storage: secure);
    final second = SecureCloudflareSessionStorage(Uri.parse('https://two.example'), storage: secure);
    await first.write('first-bearer');
    await second.write('second-bearer');
    await first.clear();
    expect(await first.read(), isNull);
    expect(await second.read(), 'second-bearer');
    expect(secure.values['hamtdaa.auth.production'], 'existing-session');
  });

  test('queued native clear waits for any in-flight bearer write', () async {
    final secure = _SecureStore()..writeGate = Completer<void>();
    final storage = SecureCloudflareSessionStorage(Uri.parse('https://stage.example'), storage: secure);
    final pending = storage.write('old-bearer');
    final clear = storage.clear();
    secure.writeGate!.complete();
    await Future.wait([pending, clear]);
    expect(await storage.read(), isNull);
  });
}

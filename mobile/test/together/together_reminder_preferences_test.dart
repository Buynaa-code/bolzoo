import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/together/together_reminders.dart';

void main() {
  test(
    'secure consent is isolated by backend origin, actor, and pair',
    () async {
      final secure = _SecureStore();
      final production = SecureTogetherReminderPreferences(
        namespace: 'https://production.example',
        storage: secure,
      );
      final staging = SecureTogetherReminderPreferences(
        namespace: 'https://staging.example',
        storage: secure,
      );
      await production.write('actor-a', 'pair-a', true);
      expect(await production.read('actor-a', 'pair-a'), isTrue);
      expect(await staging.read('actor-a', 'pair-a'), isFalse);
      expect(await production.read('actor-b', 'pair-a'), isFalse);
      expect(await production.read('actor-a', 'pair-b'), isFalse);
      await staging.write('actor-a', 'pair-a', true);
      await production.write('actor-a', 'pair-a', false);
      expect(await production.read('actor-a', 'pair-a'), isFalse);
      expect(await staging.read('actor-a', 'pair-a'), isTrue);
    },
  );
}

class _SecureStore extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

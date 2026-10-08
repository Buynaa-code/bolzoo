import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hamtdaa/auth/secure_auth_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native keychain session survives a new adapter then deletes', (tester) async {
    // A disposable key namespace, never a real login credential.
    const url = 'https://native-storage-smoke.invalid';
    final first = SecureAuthStorage(supabaseUrl: url, legacyStorage: const EmptyLocalStorage());
    try {
      await first.initialize();
      await first.persistSession('synthetic-storage-check');
      final reopened = SecureAuthStorage(supabaseUrl: url, legacyStorage: const EmptyLocalStorage());
      await reopened.initialize();
      expect(await reopened.accessToken(), 'synthetic-storage-check');
      await reopened.removePersistedSession();
      expect(await first.hasAccessToken(), isFalse);
    } finally {
      await first.removePersistedSession();
    }
  });
}

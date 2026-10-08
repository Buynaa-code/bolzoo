import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/auth_models.dart';
import 'package:hamtdaa/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('SDK refresh callbacks do not create extra account lifetimes', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false));
    final repository = SupabaseAuthRepository(client);
    final events = <AuthSession>[];
    final subscription = repository.sessions.listen(events.add);
    final session = Session(accessToken: 'test-token', tokenType: 'bearer', user: const User(id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '', email: 'a@example.com'));
    client.auth.notifyAllSubscribers(AuthChangeEvent.signedIn, session: session);
    await Future<void>.delayed(Duration.zero);
    final original = repository.current.scope;
    client.auth.notifyAllSubscribers(AuthChangeEvent.tokenRefreshed, session: session);
    client.auth.notifyAllSubscribers(AuthChangeEvent.signedIn, session: session);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(repository.current.scope, original);
    client.auth.notifyAllSubscribers(AuthChangeEvent.signedOut);
    await Future<void>.delayed(Duration.zero);
    client.auth.notifyAllSubscribers(AuthChangeEvent.signedIn, session: session);
    await Future<void>.delayed(Duration.zero);
    expect(repository.current.scope, isNot(original));
    expect(events, hasLength(3));
    await subscription.cancel();
    await repository.dispose();
    await client.dispose();
  });
}

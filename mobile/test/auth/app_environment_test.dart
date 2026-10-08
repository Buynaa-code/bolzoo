import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/auth/app_environment.dart';
import 'package:hamtdaa/main.dart';

String _keyWithRole(String role) =>
    'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';

void main() {
  const url = 'https://example.supabase.co';
  const publishable = 'sb_publishable_abcdefghijklmnopqrstuvwxyz';

  test('only a fully absent configuration enables guest mode', () {
    const absent = AppEnvironment(supabaseUrl: '', supabaseKey: '');
    expect(absent.isAbsent, isTrue);
    expect(absent.hasSupabase, isFalse);
    expect(absent.validationError, isNull);
    for (final environment in [
      const AppEnvironment(supabaseUrl: url, supabaseKey: ''),
      const AppEnvironment(supabaseUrl: '', supabaseKey: publishable),
      const AppEnvironment(supabaseUrl: 'http://example.supabase.co', supabaseKey: publishable),
      const AppEnvironment(supabaseUrl: 'https://user:password@example.supabase.co', supabaseKey: publishable),
      const AppEnvironment(supabaseUrl: url, supabaseKey: 'sb_secret_do_not_bundle'),
      AppEnvironment(supabaseUrl: url, supabaseKey: _keyWithRole('service_role')),
      AppEnvironment(supabaseUrl: url, supabaseKey: _keyWithRole('authenticated')),
      const AppEnvironment(supabaseUrl: url, supabaseKey: 'not-a-key'),
    ]) {
      expect(environment.isAbsent, isFalse);
      expect(environment.hasSupabase, isFalse);
      expect(environment.validationError, isNotNull);
      expect(environment.validationError, isNot(contains(environment.supabaseKey.isEmpty ? 'sb_secret_' : environment.supabaseKey)));
    }
  });

  test('accepts publishable and legacy anon client keys over HTTPS', () {
    expect(const AppEnvironment(supabaseUrl: url, supabaseKey: publishable).hasSupabase, isTrue);
    expect(AppEnvironment(supabaseUrl: url, supabaseKey: _keyWithRole('anon')).hasSupabase, isTrue);
  });

  testWidgets('invalid configuration shows setup error instead of guest app', (tester) async {
    await tester.pumpWidget(const AppBootstrap(environment: AppEnvironment(supabaseUrl: url, supabaseKey: 'sb_secret_do_not_bundle')));
    await tester.pump();
    expect(find.text('Нэвтрэлтийн тохиргоо буруу байна'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.textContaining('sb_secret_do_not_bundle'), findsNothing);
  });
}

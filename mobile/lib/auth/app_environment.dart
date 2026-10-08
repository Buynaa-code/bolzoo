/// Runtime configuration passed with `--dart-define`.
///
/// The publishable key is safe to ship in a client application. Never put a
/// Supabase service-role key in this file or in the Flutter bundle.
class AppEnvironment {
  const AppEnvironment({required this.supabaseUrl, required this.supabaseKey});

  factory AppEnvironment.fromDartDefines() => const AppEnvironment(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String supabaseUrl;
  final String supabaseKey;

  bool get hasSupabase =>
      supabaseUrl.startsWith('https://') &&
      Uri.tryParse(supabaseUrl)?.host.isNotEmpty == true &&
      supabaseKey.isNotEmpty &&
      !supabaseKey.contains('YOUR_') &&
      !supabaseKey.contains('placeholder');
}

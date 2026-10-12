import 'dart:convert';

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

  bool get isAbsent => supabaseUrl.isEmpty && supabaseKey.isEmpty;

  bool get hasSupabase => !isAbsent && validationError == null;

  /// This checks client-key configuration, never verifies JWT authenticity.
  /// A partial or privileged configuration must not open a separate guest store.
  String? get validationError {
    if (isAbsent) return null;
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      return 'Нэвтрэлтийн тохиргоо дутуу байна. URL болон нийтийн түлхүүр шаардлагатай.';
    }
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return 'Нэвтрэлтийн серверийн HTTPS хаяг буруу байна.';
    }
    if (supabaseKey.startsWith('sb_secret_')) {
      return 'Нууц түлхүүрийг аппд ашиглах боломжгүй. Нийтийн түлхүүр шаардлагатай.';
    }
    if (supabaseKey.contains('YOUR_') ||
        supabaseKey.toLowerCase().contains('placeholder')) {
      return 'Жишээ тохиргоог бодит нийтийн түлхүүрээр солино уу.';
    }
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]{20,}$').hasMatch(supabaseKey)) {
      return null;
    }
    final segments = supabaseKey.split('.');
    if (segments.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
        );
        if (payload is Map<String, dynamic> && payload['role'] == 'anon') {
          return null;
        }
      } on FormatException {
        // Never include key material in an error message.
      }
    }
    return 'Нэвтрэлтийн нийтийн түлхүүр буруу байна.';
  }
}

import 'main_cloudflare.dart' as cloudflare;

/// The shipped app always uses the Cloudflare identity and data boundary.
Future<void> main() => cloudflare.main();

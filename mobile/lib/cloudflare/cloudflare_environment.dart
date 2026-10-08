/// This first-stage entrypoint intentionally does not initialize Supabase.
class CloudflareEnvironment {
  const CloudflareEnvironment({required this.apiUrl, this.allowLoopback = false});

  final String apiUrl;
  final bool allowLoopback;

  String? get validationError {
    final uri = Uri.tryParse(apiUrl);
    final local = uri != null &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(allowLoopback && local && uri.scheme == 'http'))) {
      return 'Cloudflare серверийн HTTPS хаягийг тохируулна уу.';
    }
    return null;
  }

  Uri get baseUri {
    if (validationError != null) throw StateError('Invalid API configuration');
    return Uri.parse(apiUrl);
  }
}

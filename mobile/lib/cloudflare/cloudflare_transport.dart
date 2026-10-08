import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class CloudflareResponse {
  const CloudflareResponse(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

abstract interface class CloudflareTransport {
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  });
  void close();
}

/// Bearer credentials are only sent to the configured origin. Redirects are
/// refused, and transport errors never include token-bearing response bodies.
class HttpCloudflareTransport implements CloudflareTransport {
  HttpCloudflareTransport(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUri;
  // http.Client chooses IOClient on mobile and BrowserClient on the web.
  final http.Client _client;
  final _pending = <Completer<void>>{};
  bool _closed = false;
  // Calendar snapshots and account export pages can exceed 64 KiB. Keep a
  // finite limit while allowing those bounded server responses to be decoded.
  static const _maxResponseBytes = 1024 * 1024;

  @override
  Future<CloudflareResponse> send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (!path.startsWith('/v1/') || path.startsWith('//')) {
      throw ArgumentError('Invalid API path');
    }
    if (_closed) throw StateError('API transport is closed');
    final abort = Completer<void>();
    _pending.add(abort);
    try {
      return await (() async {
        final request = http.AbortableRequest(
          method,
          baseUri.resolve(path),
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers['Accept'] = 'application/json';
        request.headers['Cache-Control'] = 'no-store';
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw const FormatException('API response too large');
          }
          bytes.addAll(chunk);
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          // Decoder exceptions may contain response text, including credentials.
          throw const FormatException('Invalid API response');
        }
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid API response');
        }
        return CloudflareResponse(response.statusCode, decoded);
      })().timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    } finally {
      _pending.remove(abort);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final request in _pending) {
      if (!request.isCompleted) request.complete();
    }
    _client.close();
  }
}

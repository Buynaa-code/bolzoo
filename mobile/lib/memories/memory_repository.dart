import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../cloudflare/cloudflare_auth_repository.dart';
import '../cloudflare/cloudflare_transport.dart';
import 'memory_models.dart';

abstract interface class MemoryRepository {
  bool get isCurrent;
  String get actorId;
  Stream<void> get invalidations;
  Future<List<SharedMemory>> list(String pairId, String month);
  Future<SharedMemory> create(
    String pairId,
    String commandId,
    MemoryDraft draft,
  );
  Future<Uint8List> photo(SharedMemory memory, {bool thumbnail = false});
  Future<void> delete(SharedMemory memory, String commandId);
  Future<void> dispose();
}

/// Every instance and response belongs to one exact login, never the current
/// mutable account. Private images are fetched with credentials, not public URLs.
class CloudflareMemoryRepository implements MemoryRepository {
  CloudflareMemoryRepository(this.auth, {Uri? baseUri, http.Client? client})
    : _credential = auth.credential,
      _client = client ?? http.Client(),
      baseUri = baseUri ?? endpointFor(auth) {
    if (this.baseUri.scheme != 'https' ||
        this.baseUri.host.isEmpty ||
        this.baseUri.userInfo.isNotEmpty ||
        this.baseUri.hasQuery ||
        this.baseUri.hasFragment)
      throw ArgumentError('Invalid memories origin');
    _subscription = auth.sessions.listen((_) {
      if (!isCurrent && !_disposed) _events.add(null);
    });
  }
  static Uri endpointFor(CloudflareAuthRepository auth) {
    const override = String.fromEnvironment('CLOUDFLARE_MEMORIES_API_URL');
    if (override.isNotEmpty) return Uri.parse(override);
    final transport = auth.transport;
    final staging =
        transport is HttpCloudflareTransport &&
        transport.baseUri.host == 'hamtdaa-api-staging.mendmedey.workers.dev';
    return Uri.parse(
      'https://nandin-moch-memories-${staging ? 'staging' : 'production'}.mendmedey.workers.dev',
    );
  }

  final CloudflareAuthRepository auth;
  final CloudflareCredential? _credential;
  final http.Client _client;
  final Uri baseUri;
  final _events = StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <Completer<void>>{};
  bool _disposed = false;
  @override
  bool get isCurrent =>
      !_disposed && _credential != null && auth.accepts(_credential);
  @override
  String get actorId => _credential?.scope.userId ?? '';
  @override
  Stream<void> get invalidations => _events.stream;
  void _check() {
    if (!isCurrent) throw const MemoryFailure('unauthenticated');
  }

  Future<Uint8List> _request(
    String path, {
    Map<String, dynamic>? body,
    bool image = false,
    int maxBytes = 1200 * 1024,
  }) async {
    _check();
    final abort = Completer<void>();
    _pending.add(abort);
    try {
      return await (() async {
        final request = http.AbortableRequest(
          body == null ? 'GET' : 'POST',
          baseUri.resolve(path),
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers['Authorization'] = 'Bearer ${_credential!.token}';
        request.headers['Accept'] = image ? 'image/jpeg' : 'application/json';
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        final response = await _client.send(request);
        final bytes = BytesBuilder(copy: false);
        var length = 0;
        await for (final part in response.stream) {
          length += part.length;
          if (length > maxBytes) throw const MemoryFailure('invalid_response');
          bytes.add(part);
        }
        _check();
        if (response.statusCode == 401) {
          await auth.reject(_credential);
          throw const MemoryFailure('unauthenticated');
        }
        final data = bytes.takeBytes();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          String code = 'unavailable';
          try {
            final error = jsonDecode(utf8.decode(data));
            if (error is Map && error['code'] is String)
              code = error['code'] as String;
          } catch (_) {}
          throw MemoryFailure(code);
        }
        if (image &&
            response.headers['content-type']?.split(';').first != 'image/jpeg')
          throw const MemoryFailure('invalid_response');
        if (image &&
            (data.length < 4 ||
                data[0] != 0xff ||
                data[1] != 0xd8 ||
                data[data.length - 2] != 0xff ||
                data.last != 0xd9)) {
          throw const MemoryFailure('invalid_response');
        }
        return data;
      })().timeout(const Duration(seconds: 35));
    } on MemoryFailure {
      rethrow;
    } catch (_) {
      _check();
      throw const MemoryFailure('unavailable');
    } finally {
      _pending.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Map<String, dynamic>> _json(
    String path,
    Map<String, dynamic> body, {
    int maxBytes = 1200 * 1024,
  }) async {
    try {
      final value = jsonDecode(
        utf8.decode(await _request(path, body: body, maxBytes: maxBytes)),
      );
      if (value is! Map<String, dynamic> || value['ok'] != true)
        throw const MemoryFailure('invalid_response');
      return value;
    } on MemoryFailure {
      rethrow;
    } catch (_) {
      throw const MemoryFailure('invalid_response');
    }
  }

  @override
  Future<List<SharedMemory>> list(String pairId, String month) async {
    final value = await _json('/v1/memories/list', {
      'expected_pair_id': pairId,
      'month': month,
    }, maxBytes: 4 * 1024 * 1024);
    if (value['pair_id'] != pairId || value['memories'] is! List)
      throw const MemoryFailure('invalid_response');
    try {
      final items = (value['memories'] as List)
          .map(
            (v) => SharedMemory.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
      if (items.length > 310 ||
          items.any((v) => v.pairId != pairId || !v.day.startsWith('$month-')))
        throw const FormatException();
      return List.unmodifiable(items);
    } catch (_) {
      throw const MemoryFailure('invalid_response');
    }
  }

  @override
  Future<SharedMemory> create(
    String pairId,
    String commandId,
    MemoryDraft draft,
  ) async {
    if (draft.image.photo.isEmpty ||
        draft.image.thumbnail.isEmpty ||
        draft.image.photo.length > 768 * 1024 ||
        draft.image.thumbnail.length > 64 * 1024) {
      throw const MemoryFailure('photo_too_large');
    }
    final value = await _json('/v1/memories/create', {
      'expected_pair_id': pairId,
      'command_id': commandId,
      'day': draft.day,
      'title': draft.title,
      'note': draft.note,
      'sticker': draft.sticker,
      'photo_base64': base64Encode(draft.image.photo),
      'thumbnail_base64': base64Encode(draft.image.thumbnail),
    });
    try {
      final memory = SharedMemory.fromJson(
        Map<String, dynamic>.from(value['memory'] as Map),
      );
      if (memory.pairId != pairId ||
          memory.creatorId != actorId ||
          memory.day != draft.day)
        throw const FormatException();
      return memory;
    } catch (_) {
      throw const MemoryFailure('invalid_response');
    }
  }

  @override
  Future<Uint8List> photo(SharedMemory memory, {bool thumbnail = false}) {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(memory.id))
      throw const MemoryFailure('invalid_response');
    return _request(
      '/v1/memories/${memory.id}/${thumbnail ? 'thumbnail' : 'photo'}',
      image: true,
      maxBytes: (thumbnail ? 64 : 768) * 1024,
    );
  }

  @override
  Future<void> delete(SharedMemory memory, String commandId) async {
    final value = await _json('/v1/memories/delete', {
      'expected_pair_id': memory.pairId,
      'id': memory.id,
      'expected_version': memory.version,
      'command_id': commandId,
    });
    if (value['deleted'] != true) throw const MemoryFailure('invalid_response');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
    await _subscription.cancel();
    await _events.close();
  }
}

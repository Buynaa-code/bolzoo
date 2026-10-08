import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'content_repository.dart';

typedef ContentRpcTransport =
    Future<dynamic> Function(String name, Map<String, Object?> parameters);

/// Bound to one authenticated account AND login session. Token refresh is allowed;
/// a logout/login or account switch invalidates this adapter permanently.
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(SupabaseClient client)
    : _client = client,
      _accountId = client.auth.currentUser?.id ?? '',
      _rpcTransport = ((name, params) => client.rpc(name, params: params)),
      _sessionCurrent = (() => false) {
    final sessionId = _sessionId(client.auth.currentSession);
    _sessionCurrent = () =>
        _accountId.isNotEmpty &&
        sessionId != null &&
        client.auth.currentUser?.id == _accountId &&
        _sessionId(client.auth.currentSession) == sessionId;
  }

  SupabaseContentRepository.withTransport({
    required String accountId,
    required ContentRpcTransport rpc,
    required bool Function() sessionCurrent,
  }) : _client = null,
       _accountId = accountId,
       _rpcTransport = rpc,
       _sessionCurrent = sessionCurrent;

  final SupabaseClient? _client;
  final String _accountId;
  final ContentRpcTransport _rpcTransport;
  bool Function() _sessionCurrent;
  bool _valid = true;
  @override
  String get userId => _accountId;

  static String? _sessionId(Session? session) {
    try {
      if (session == null) return null;
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(session.accessToken.split('.')[1]),
                  ),
                ),
              )
              as Map;
      return payload['session_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _checkSession() {
    if (!_valid || !_sessionCurrent()) {
      _valid = false;
      throw const ContentException('unauthenticated');
    }
  }

  Future<T> _request<T>(Future<T> Function() action) async {
    _checkSession();
    try {
      final result = await action().timeout(const Duration(seconds: 20));
      _checkSession();
      return result;
    } on ContentException catch (error) {
      if (error.code == 'unauthenticated') _valid = false;
      rethrow;
    } on AuthException {
      _valid = false;
      throw const ContentException('unauthenticated');
    } on PostgrestException catch (error) {
      if (const {
        '42501',
        'PGRST301',
        'PGRST302',
        'PGRST303',
      }.contains(error.code)) {
        _valid = false;
        throw const ContentException('unauthenticated');
      }
      throw const ContentException('network');
    } catch (_) {
      // Never surface transport bodies, SQL details, or token-bearing headers.
      _checkSession();
      throw const ContentException('network');
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String name, [
    Map<String, Object?>? args,
  ]) => _request(() async {
    final raw = await _rpcTransport('hamtdaa_content_$name', args ?? const {});
    final result = Map<String, dynamic>.from(raw as Map);
    if (result['ok'] != true) {
      throw ContentException(result['code'] as String? ?? 'network');
    }
    return result;
  });

  ContentItem _parseItem(Object? raw) {
    try {
      final data = Map<String, dynamic>.from(raw as Map);
      final item = ContentItem.fromJson(data);
      if (!const {'owner', 'partner'}.contains(data['role']) ||
          (!item.partner && item.ownerId != _accountId) ||
          (item.partner &&
              (item.ownerId == _accountId || item.pairId == null))) {
        _valid = false;
        throw const ContentException('unauthenticated');
      }
      return item;
    } on ContentException {
      rethrow;
    } catch (_) {
      throw const ContentException('network');
    }
  }

  Future<ContentItem> _item(String name, Map<String, Object?> args) async =>
      _parseItem((await _rpc(name, args))['item']);
  @override
  Future<List<ContentItem>> snapshot() async {
    final items = (await _rpc('snapshot'))['items'];
    if (items is! List) throw const ContentException('network');
    return items.map(_parseItem).toList();
  }

  @override
  Future<ContentItem> save({
    required String commandId,
    required String id,
    required String kind,
    required Map<String, Object?> payload,
    required bool shared,
    int? expectedVersion,
  }) => _item('save', {
    'p_command_id': commandId,
    'p_id': id,
    'p_kind': kind,
    'p_payload': payload,
    'p_shared': shared,
    'p_expected_version': expectedVersion,
  });
  @override
  Future<ContentItem> delete({
    required String commandId,
    required String id,
    required int expectedVersion,
  }) => _item('delete', {
    'p_command_id': commandId,
    'p_id': id,
    'p_expected_version': expectedVersion,
  });
  @override
  Future<ContentItem> respond({
    required String commandId,
    required String id,
    required int expectedVersion,
    required String action,
    DateTime? proposedAt,
  }) => _item('respond', {
    'p_command_id': commandId,
    'p_id': id,
    'p_expected_version': expectedVersion,
    'p_action': action,
    'p_proposed_at': proposedAt?.toIso8601String(),
  });
  @override
  Future<ContentItem> react({
    required String commandId,
    required String id,
    required bool liked,
  }) =>
      _item('react', {'p_command_id': commandId, 'p_id': id, 'p_liked': liked});
  @override
  Future<ContentItem> comment({
    required String commandId,
    required String id,
    required String text,
  }) =>
      _item('comment', {'p_command_id': commandId, 'p_id': id, 'p_text': text});
  @override
  Future<String> uploadPhoto(
    String itemId,
    Uint8List bytes,
    String extension,
  ) => _request(() async {
    final result = await _client!.functions.invoke(
      'hamtdaa-media',
      queryParameters: {'item': itemId, 'ext': extension},
      body: bytes,
      headers: {'Content-Type': 'application/octet-stream'},
    );
    if (result.status != 200 ||
        result.data is! Map ||
        result.data['key'] is! String) {
      throw const ContentException('media_upload');
    }
    return result.data['key'] as String;
  });
  @override
  Future<Uint8List> downloadPhoto(String key) => _request(() async {
    final result = await _client!.functions.invoke(
      'hamtdaa-media',
      method: HttpMethod.get,
      queryParameters: {'key': key},
    );
    if (result.status != 200 || result.data is! List<int>) {
      throw const ContentException('media_download');
    }
    return Uint8List.fromList(result.data as List<int>);
  });
}

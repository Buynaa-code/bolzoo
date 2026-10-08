import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AccountRepository {
  String get userId;
  bool get sessionCurrent;
  Future<Map<String, dynamic>> exportData();
  Future<Uint8List> downloadMedia(String key);
  Future<void> deleteAccount();
}

class AccountOperationException implements Exception {
  const AccountOperationException(this.code);
  final String code;
}

typedef AccountTransport = Future<Object?> Function(Map<String, Object?> body);

/// Permanently bound to a single login, including across token refreshes.
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(SupabaseClient client)
    : userId = client.auth.currentUser?.id ?? '',
      _transport = ((body) {
        // Capture before the SDK's asynchronous body encoding/token lookup.
        // Its auth client preserves explicit per-request Authorization headers.
        final token = client.auth.currentSession?.accessToken ?? '';
        return client.functions.invoke('hamtdaa-account', body: body,
          headers: {'Authorization': 'Bearer $token'}).then((r) => r.data);
      }) {
    final session = _sessionId(client.auth.currentSession);
    _isCurrent = () => userId.isNotEmpty && session != null &&
        client.auth.currentUser?.id == userId &&
        _sessionId(client.auth.currentSession) == session;
  }

  SupabaseAccountRepository.withTransport({
    required this.userId,
    required AccountTransport transport,
    required bool Function() sessionCurrent,
  }) : _transport = transport, _isCurrent = sessionCurrent;

  @override
  final String userId;
  final AccountTransport _transport;
  late final bool Function() _isCurrent;
  bool _invalid = false;

  @override
  bool get sessionCurrent => !_invalid && _isCurrent();

  static String? _sessionId(Session? session) {
    try {
      if (session == null) return null;
      return (jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(session.accessToken.split('.')[1]),
      ))) as Map)['session_id'] as String?;
    } catch (_) { return null; }
  }

  void _check() {
    if (!sessionCurrent) {
      _invalid = true;
      throw const AccountOperationException('session_changed');
    }
  }

  Future<Object?> _request(Map<String, Object?> body) async {
    _check();
    try {
      final result = await _transport(body).timeout(const Duration(seconds: 90));
      _check();
      if (result is Map && result['ok'] != true) {
        throw const AccountOperationException('unavailable');
      }
      return result;
    } on AccountOperationException { rethrow; }
    catch (_) {
      _check();
      // Transport errors may include headers, SQL or sensitive response bodies.
      throw const AccountOperationException('unavailable');
    }
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    final raw = await _request({'action': 'export'});
    if (raw is! Map || raw['export'] is! Map) {
      throw const AccountOperationException('invalid_export');
    }
    final data = Map<String, dynamic>.from(raw['export'] as Map);
    if (data['account'] is! Map || data['account']['userId'] != userId ||
        data['schemaVersion'] != 1 || data['items'] is! List || data['media'] is! List) {
      throw const AccountOperationException('invalid_export');
    }
    return data;
  }

  @override
  Future<Uint8List> downloadMedia(String key) async {
    if (!key.startsWith('$userId/')) {
      throw const AccountOperationException('invalid_media');
    }
    final raw = await _request({'action': 'download', 'key': key});
    if (raw is! Uint8List || raw.isEmpty || raw.length > 10 * 1024 * 1024) {
      throw const AccountOperationException('invalid_media');
    }
    return raw;
  }

  @override
  Future<void> deleteAccount() async {
    final raw = await _request({'action': 'delete', 'confirmation': 'DELETE'});
    if (raw is! Map || raw['deleted'] != true) {
      throw const AccountOperationException('unavailable');
    }
  }
}

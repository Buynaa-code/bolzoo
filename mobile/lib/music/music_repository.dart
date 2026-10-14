import '../cloudflare/cloudflare_auth_repository.dart';
import 'music_track.dart';

abstract interface class MusicRepository {
  bool get isCurrent;
  Future<List<MusicTrack>> search(String query);
}

class CloudflareMusicRepository implements MusicRepository {
  CloudflareMusicRepository(this._auth) : _credential = _auth.credential;
  final CloudflareAuthRepository _auth;
  final CloudflareCredential? _credential;
  @override
  bool get isCurrent => _credential != null && _auth.accepts(_credential);
  void _check() {
    if (!isCurrent) throw const MusicFailure('unauthenticated');
  }

  @override
  Future<List<MusicTrack>> search(String query) async {
    _check();
    final term = query.trim();
    if (term.length < 2 || term.length > 100) {
      throw const MusicFailure('validation');
    }
    try {
      final response = await _auth.transport.send(
        'POST',
        '/v1/music/search',
        token: _credential!.token,
        body: {'query': term},
      );
      _check();
      if (response.status == 401) {
        await _auth.reject(_credential);
        throw const MusicFailure('unauthenticated');
      }
      if (response.status != 200 || response.body['ok'] != true) {
        throw MusicFailure(
          response.body['code'] is String
              ? response.body['code'] as String
              : 'invalid_response',
        );
      }
      final tracks = response.body['tracks'];
      if (tracks is! List || tracks.length > 20) {
        throw const MusicFailure('invalid_response');
      }
      try {
        return List.unmodifiable(
          tracks.map(
            (e) => MusicTrack.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );
      } catch (_) {
        throw const MusicFailure('invalid_response');
      }
    } on MusicFailure {
      rethrow;
    } catch (_) {
      _check();
      throw const MusicFailure('network_error');
    }
  }
}

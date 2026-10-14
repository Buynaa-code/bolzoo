/// Only a YouTube identifier and display text travel with an invitation.
/// URLs are constructed here, never accepted from an API response.
class MusicTrack {
  const MusicTrack({
    required this.videoId,
    required this.title,
    required this.channelTitle,
  });
  final String videoId, title, channelTitle;
  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  Uri get watchUrl => Uri.https('www.youtube.com', '/watch', {'v': videoId});
  Uri get thumbnailUrl =>
      Uri.https('i.ytimg.com', '/vi/$videoId/mqdefault.jpg');
  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'title': title,
    'channel_title': channelTitle,
  };
  factory MusicTrack.fromJson(Map<String, dynamic> value) {
    final id = value['video_id'],
        title = value['title'],
        channel = value['channel_title'];
    if (id is! String ||
        id.length != 11 ||
        !_id.hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 200 ||
        channel is! String ||
        channel.length > 200 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch('$title$channel')) {
      throw const FormatException('Invalid music');
    }
    return MusicTrack(
      videoId: id,
      title: title.trim(),
      channelTitle: channel.trim(),
    );
  }

  static MusicTrack? fromYouTubeLink(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    String? id;
    if (uri.host == 'youtu.be' && uri.pathSegments.length == 1) {
      id = uri.pathSegments.first;
    } else if (const {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
    }.contains(uri.host)) {
      if (uri.path == '/watch') id = uri.queryParameters['v'];
      if (uri.pathSegments.length == 2 &&
          const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments.last;
      }
    }
    if (id == null || id.length != 11 || !_id.hasMatch(id)) return null;
    return MusicTrack(
      videoId: id,
      title: 'YouTube дуу',
      channelTitle: 'YouTube',
    );
  }
}

class MusicFailure implements Exception {
  const MusicFailure(this.code);
  final String code;
  String get message => switch (code) {
    'unauthenticated' => 'Нэвтрэлт дууслаа. Дахин нэвтрээрэй.',
    'music_unavailable' =>
      'Дууны хайлт түр боломжгүй байна. YouTube холбоосоор дуугаа нэмж болно.',
    'quota_exceeded' ||
    'rate_limited' => 'Хайлт олширлоо. Түр хүлээгээд дахин хайгаарай.',
    'validation' => 'Дуу эсвэл дуучныхаа нэрийг 2–100 тэмдэгтэд бичээрэй.',
    _ => 'Дуу хайж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
  };
}

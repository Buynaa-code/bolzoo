import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/music/music_track.dart';
import 'package:hamtdaa/together/together_models.dart';

import '../together/together_fakes.dart';
import 'music_repository_test.dart' show trackJson;

void main() {
  test('only supported HTTPS YouTube hosts and video paths are accepted', () {
    for (final link in [
      'https://youtu.be/dQw4w9WgXcQ',
      ' https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=20 ',
      'https://youtube.com/shorts/dQw4w9WgXcQ',
      'https://m.youtube.com/embed/dQw4w9WgXcQ',
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/live/dQw4w9WgXcQ',
    ]) {
      final track = MusicTrack.fromYouTubeLink(link);
      expect(track?.videoId, 'dQw4w9WgXcQ', reason: link);
      expect(
        track?.watchUrl.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    }
  });

  test(
    'links cannot smuggle credentials, arbitrary hosts, schemes or path fragments',
    () {
      for (final link in [
        'http://youtube.com/watch?v=dQw4w9WgXcQ',
        'javascript:alert(1)',
        'file:///watch?v=dQw4w9WgXcQ',
        'https://youtube.com.attacker.test/watch?v=dQw4w9WgXcQ',
        'https://youtube.com@attacker.test/watch?v=dQw4w9WgXcQ',
        'https://user:password@youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com:8443/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ/more',
        'https://youtube.com/playlist?list=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=../../thing',
        'https://youtube.com/watch?v=dQw4w9WgXcQmore',
        'https://youtube.com/watch#v=dQw4w9WgXcQ',
        'https://attacker.test/?v=dQw4w9WgXcQ',
        'dQw4w9WgXcQ',
      ]) {
        expect(MusicTrack.fromYouTubeLink(link), isNull, reason: link);
      }
    },
  );

  test('legacy events remain valid and music survives event parsing', () {
    expect(TogetherEvent.fromJson(eventJson()).music, isNull);
    expect(
      TogetherEvent.fromJson(eventJson(music: trackJson)).music?.videoId,
      'dQw4w9WgXcQ',
    );
    expect(
      () => TogetherEvent.fromJson(
        eventJson(music: {...trackJson, 'video_id': 'bad'}),
      ),
      throwsFormatException,
    );
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/music/music_repository.dart';
import 'package:hamtdaa/music/music_track.dart';
import 'package:hamtdaa/music/music_widgets.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

import '../together/together_fakes.dart';
import 'music_repository_test.dart' show trackJson;

class MusicFake implements MusicRepository {
  @override
  bool isCurrent = true;
  final queries = <String>[];
  Future<List<MusicTrack>> Function(String)? onSearch;
  @override
  Future<List<MusicTrack>> search(String query) async {
    queries.add(query);
    return onSearch == null
        ? [MusicTrack.fromJson(trackJson)]
        : onSearch!(query);
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late MusicFake music;
  final launches = <MethodCall>[];
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  setUp(() {
    music = MusicFake();
    launches.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          launches.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
  });
  Future<void> mountPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MusicPicker(repository: music),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('editing a query invalidates the old in-flight results', (
    tester,
  ) async {
    final old = Completer<List<MusicTrack>>(),
        fresh = Completer<List<MusicTrack>>();
    music.onSearch = (query) => query == 'old' ? old.future : fresh.future;
    await mountPicker(tester);
    await tester.enterText(find.byKey(const Key('musicQuery')), 'old');
    await tester.tap(find.byKey(const Key('searchMusic')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('musicQuery')), 'new');
    await tester.pump();
    await tester.tap(find.byKey(const Key('searchMusic')));
    await tester.pump();
    fresh.complete([
      MusicTrack.fromJson({...trackJson, 'title': 'Fresh result'}),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh result'), findsOneWidget);
    old.complete([
      MusicTrack.fromJson({...trackJson, 'title': 'Obsolete result'}),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh result'), findsOneWidget);
    expect(find.text('Obsolete result'), findsNothing);
    expect(launches, isEmpty);
  });

  testWidgets('provider errors allow retry without showing stale cards', (
    tester,
  ) async {
    music.onSearch = (_) async => throw const MusicFailure('music_unavailable');
    await mountPicker(tester);
    await tester.enterText(find.byKey(const Key('musicQuery')), 'Our song');
    await tapKey(tester, 'searchMusic');
    expect(find.byKey(const Key('musicSearchError')), findsOneWidget);
    expect(find.byType(MusicTrackCard), findsNothing);
    music.onSearch = (_) async => [MusicTrack.fromJson(trackJson)];
    await tester.tap(find.text('Дахин хайх'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('musicSearchError')), findsNothing);
    expect(find.text('Our song'), findsNWidgets(2));
  });

  testWidgets('revoked search scope cannot reveal a late result', (
    tester,
  ) async {
    final result = Completer<List<MusicTrack>>();
    music.onSearch = (_) => result.future;
    await mountPicker(tester);
    await tester.enterText(find.byKey(const Key('musicQuery')), 'Our song');
    await tester.tap(find.byKey(const Key('searchMusic')));
    await tester.pump();
    music.isCurrent = false;
    result.complete([MusicTrack.fromJson(trackJson)]);
    await tester.pumpAndSettle();
    expect(find.byType(MusicTrackCard), findsNothing);
    expect(launches, isEmpty);
  });

  testWidgets(
    'a valid pasted YouTube link is selected without search or autoplay',
    (tester) async {
      MusicTrack? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<MusicTrack>(
                    MaterialPageRoute(
                      builder: (_) => MusicPicker(repository: music),
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('musicQuery')),
        'https://youtu.be/dQw4w9WgXcQ',
      );
      await tapKey(tester, 'searchMusic');
      expect(selected?.videoId, 'dQw4w9WgXcQ');
      expect(music.queries, isEmpty);
      expect(launches, isEmpty);
    },
  );

  testWidgets(
    'playback falls back to the external YouTube page when the in-app browser fails',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launches.add(call);
            return launches.length > 1;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicTrackCard(track: MusicTrack.fromJson(trackJson)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(launches, isEmpty);
      await tapKey(tester, 'playInvitationMusic');
      expect(launches, hasLength(2));
      expect(launches.first.arguments['useWebView'], isTrue);
      expect(launches.last.arguments['useWebView'], isFalse);
      expect(
        launches.map((call) => call.arguments['url']),
        everyElement('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );
    },
  );

  testWidgets(
    'unavailable playback reports an error without removing the invitation song',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launches.add(call);
            return false;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicTrackCard(track: MusicTrack.fromJson(trackJson)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'playInvitationMusic');
      expect(launches, hasLength(2));
      expect(
        find.text('YouTube нээгдсэнгүй. Дахин оролдоорой.'),
        findsOneWidget,
      );
      expect(find.text('Our song'), findsOneWidget);
    },
  );

  group('shared invitation', () {
    late TogetherFakeRepository dates;
    late TogetherController controller;
    late CloudflareAuthRepository auth;
    setUp(() {
      dates = TogetherFakeRepository();
      controller = TogetherController(repository: dates, now: () => today);
      auth = CloudflareAuthRepository(
        transport: TogetherTransport(),
        storage: TogetherStorage(),
      );
    });
    tearDown(() async {
      controller.dispose();
      await auth.dispose();
    });
    Future<void> mount(WidgetTester tester, {String? eventId}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: TogetherScreen(
            auth: auth,
            controller: controller,
            musicRepository: music,
            initialEventId: eventId,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('choose, save, reopen, preserve on edit, remove and reopen', (
      tester,
    ) async {
      await mount(tester);
      await tapKey(tester, 'togetherCreate');
      await tester.enterText(
        find.byKey(const Key('togetherTitle')),
        'Бидний болзоо',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapKey(tester, 'pickInvitationMusic');
      await tester.enterText(find.byKey(const Key('musicQuery')), 'Our song');
      await tapKey(tester, 'searchMusic');
      await tapKey(tester, 'selectMusic:dQw4w9WgXcQ');
      expect(find.text('Our song'), findsOneWidget);
      expect(dates.commands, isEmpty);
      expect(launches, isEmpty);
      await tapKey(tester, 'togetherSaveEvent');
      expect(dates.commands.single.body['music'], trackJson);
      await tapKey(tester, 'togetherEventevent-1');
      expect(find.text('YouTube дуу'), findsOneWidget);
      expect(
        tester
            .widget<MusicTrackCard>(find.byType(MusicTrackCard))
            .track
            .videoId,
        'dQw4w9WgXcQ',
      );
      await tapKey(tester, 'togetherEdit');
      await tester.enterText(
        find.byKey(const Key('togetherTitle')),
        'Шинэ нэр',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapKey(tester, 'togetherSaveEvent');
      expect(
        (dates.commands.last.body['music'] as Map)['video_id'],
        'dQw4w9WgXcQ',
      );
      await tapKey(tester, 'togetherEventevent-1');
      expect(find.text('YouTube дуу'), findsOneWidget);
      await tapKey(tester, 'togetherEdit');
      await tapKey(tester, 'removeInvitationMusic');
      await tapKey(tester, 'togetherSaveEvent');
      expect(dates.commands.last.body.containsKey('music'), isTrue);
      expect(dates.commands.last.body['music'], isNull);
      await tapKey(tester, 'togetherEventevent-1');
      expect(find.byType(MusicTrackCard), findsNothing);
      expect(launches, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'recipient sees persisted music but playback requires an explicit tap',
      (tester) async {
        dates.value = stateJson(
          events: [eventJson(creator: 'b', music: trackJson)],
        );
        await mount(tester, eventId: 'event-1');
        expect(find.text('Our song'), findsOneWidget);
        expect(find.byKey(const Key('togetherEdit')), findsNothing);
        expect(find.byKey(const Key('togetherAccept')), findsOneWidget);
        expect(launches, isEmpty);
        await tapKey(tester, 'playInvitationMusic');
        expect(launches, hasLength(1));
        expect(
          launches.single.arguments['url'],
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        );
        expect(launches.single.arguments['useWebView'], isTrue);
        expect(dates.commands, isEmpty);
      },
    );

    testWidgets(
      'previewing a song in the browser preserves the local invitation draft and picker result',
      (tester) async {
        await mount(tester);
        await tapKey(tester, 'togetherCreate');
        await tester.enterText(
          find.byKey(const Key('togetherTitle')),
          'Бидний онцгой орой',
        );
        await tester.enterText(
          find.byKey(const Key('togetherLocation')),
          'Бидний кафе',
        );
        await tester.enterText(
          find.byKey(const Key('togetherNote')),
          'Дуу сонгохоос өмнө бичсэн зурвас',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tapKey(tester, 'pickInvitationMusic');
        await tester.enterText(find.byKey(const Key('musicQuery')), 'Our song');
        await tapKey(tester, 'searchMusic');
        await tapKey(tester, 'playInvitationMusic');
        expect(launches, hasLength(1));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 2));
        expect(dates.commands, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        await tapKey(tester, 'selectMusic:dQw4w9WgXcQ');
        expect(find.byType(MusicPicker), findsNothing);
        expect(find.text('Our song'), findsOneWidget);
        await tapKey(tester, 'togetherSaveEvent');
        final command = dates.commands.single;
        expect(command.body['title'], 'Бидний онцгой орой');
        expect(command.body['location'], 'Бидний кафе');
        expect(command.body['note'], 'Дуу сонгохоос өмнө бичсэн зурвас');
        expect(command.body['music'], trackJson);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'unlinking while music is previewed discards the old pair draft',
      (tester) async {
        await mount(tester);
        await tapKey(tester, 'togetherCreate');
        await tester.enterText(
          find.byKey(const Key('togetherTitle')),
          'Өмнөх хосын хувийн урилга',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tapKey(tester, 'pickInvitationMusic');
        await tester.enterText(find.byKey(const Key('musicQuery')), 'Our song');
        await tapKey(tester, 'searchMusic');
        await tapKey(tester, 'playInvitationMusic');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 2));
        dates.value = stateJson(paired: false);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'selectMusic:dQw4w9WgXcQ');
        expect(find.text('Хосоороо холбогдоорой'), findsOneWidget);
        expect(find.text('Өмнөх хосын хувийн урилга'), findsNothing);
        expect(find.byKey(const Key('togetherSaveEvent')), findsNothing);
        expect(dates.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'older calendar writers omit music without deleting it; explicit null clears it',
      () async {
        dates.value = stateJson(events: [eventJson(music: trackJson)]);
        final body = {...eventJson(), 'expected_version': 1}..remove('music');
        await dates.mutate(TogetherCommand('calendar/update', pairId, body));
        expect(
          (await dates.state('2026-10')).events.single.music?.videoId,
          'dQw4w9WgXcQ',
        );
        await dates.mutate(
          TogetherCommand('calendar/update', pairId, {...body, 'music': null}),
        );
        expect((await dates.state('2026-10')).events.single.music, isNull);
      },
    );
  });
}

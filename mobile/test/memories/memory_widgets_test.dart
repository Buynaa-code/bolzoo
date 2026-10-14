import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/memories/memory_detail.dart';
import 'package:hamtdaa/memories/memory_editor.dart';
import 'package:hamtdaa/memories/memory_models.dart';
import 'package:hamtdaa/memories/memory_sticker.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'package:image/image.dart' as img;

Uint8List _photo() => img.encodeJpg(
  img.Image(width: 40, height: 30)..clear(img.ColorRgb8(210, 90, 150)),
);
SharedMemory _memory(String id) => SharedMemory(
  id: id,
  pairId: 'pair',
  creatorId: 'a',
  day: '2026-10-08',
  title: 'Кофе уусан өдөр',
  note: 'Намрын нар дулаахан байлаа.',
  sticker: 'rounded',
  version: 1,
  createdAt: DateTime.utc(2026, 10, 8),
);

Future<void> _mount(WidgetTester tester, Widget body) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SafeArea(child: body)),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester) async {
  final finder = find.byKey(const Key('memoryChoosePhoto'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (tester.widget<OutlinedButton>(finder).onPressed == null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Photo processing did not finish');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'photo permission refusal keeps the draft and permits a later selection',
    (tester) async {
      var picks = 0;
      final saved = <MemoryDraft>[];
      await _mount(
        tester,
        MemoryEditor(
          day: '2026-10-14',
          picker: () async {
            if (++picks == 1) {
              throw PlatformException(code: 'photo_access_denied');
            }
            return _photo();
          },
          onSave: (draft) async {
            saved.add(draft);
            return true;
          },
          onCancel: () {},
        ),
      );
      await tester.enterText(
        find.byKey(const Key('memoryTitle')),
        'Бидний өдөр',
      );
      await tester.enterText(
        find.byKey(const Key('memoryNote')),
        'Хамтдаа алхсан.',
      );
      await _choose(tester);
      expect(
        find.text(
          'Зураг сонгож чадсангүй. Зургийн хандалтаа шалгаад дахин оролдоорой.',
        ),
        findsOneWidget,
      );
      expect(saved, isEmpty);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('memoryChoosePhoto')))
            .onPressed,
        isNotNull,
      );
      await _choose(tester);
      expect(find.byKey(const Key('memoryEditorError')), findsNothing);
      await _tap(tester, 'memorySave');
      expect(saved, hasLength(1));
      expect(saved.single.title, 'Бидний өдөр');
      expect(saved.single.note, 'Хамтдаа алхсан.');
      expect(saved.single.day, '2026-10-14');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor validates required title and photo; picker cancel remains usable',
    (tester) async {
      var saves = 0, cancelled = 0;
      await _mount(
        tester,
        MemoryEditor(
          day: '2026-10-08',
          picker: () async => null,
          onSave: (_) async {
            saves++;
            return true;
          },
          onCancel: () => cancelled++,
        ),
      );
      await _tap(tester, 'memorySave');
      expect(find.text('Дурсамжийн нэрээ оруулаарай.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('memoryTitle')), 'Кофе');
      await _tap(tester, 'memorySave');
      expect(find.text('Дурсамжийнхаа зургийг сонгоорой.'), findsOneWidget);
      await _choose(tester);
      expect(find.byKey(const Key('memoryEditorError')), findsNothing);
      expect(saves, 0);
      await _tap(tester, 'memoryCancel');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(cancelled, 0);
      await tester.tap(find.byKey(const Key('memoryDiscard')));
      await tester.pumpAndSettle();
      expect(cancelled, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed save retains photo and diary; retry sends same selected day and style',
    (tester) async {
      final drafts = <MemoryDraft>[];
      await _mount(
        tester,
        MemoryEditor(
          day: '2026-10-08',
          picker: () async => _photo(),
          onSave: (draft) async {
            drafts.add(draft);
            return drafts.length > 1;
          },
          onCancel: () {},
        ),
      );
      await _choose(tester);
      await tester.tap(find.text('Полароид'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('memoryTitle')),
        '  Кофе уусан өдөр  ',
      );
      await tester.enterText(
        find.byKey(const Key('memoryNote')),
        '  Хамтдаа ярилцсан.  ',
      );
      await _tap(tester, 'memorySave');
      expect(find.byKey(const Key('memoryEditorError')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('memoryTitle')))
            .controller!
            .text,
        '  Кофе уусан өдөр  ',
      );
      expect(
        tester.widget<MemorySticker>(find.byType(MemorySticker)).bytes,
        isNotNull,
      );
      await _tap(tester, 'memorySave');
      expect(drafts, hasLength(2));
      expect(drafts.last.day, '2026-10-08');
      expect(drafts.last.title, 'Кофе уусан өдөр');
      expect(drafts.last.note, 'Хамтдаа ярилцсан.');
      expect(drafts.last.sticker, 'polaroid');
      expect(identical(drafts.first.image, drafts.last.image), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save and cancel cannot double-submit while saving', (
    tester,
  ) async {
    final saving = Completer<bool>();
    var calls = 0;
    await _mount(
      tester,
      MemoryEditor(
        day: '2026-10-08',
        picker: () async => _photo(),
        onSave: (_) {
          calls++;
          return saving.future;
        },
        onCancel: () {},
      ),
    );
    await _choose(tester);
    await tester.enterText(find.byKey(const Key('memoryTitle')), 'Сайхан өдөр');
    await tester.ensureVisible(find.byKey(const Key('memorySave')));
    await tester.tap(find.byKey(const Key('memorySave')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('memorySave')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('memoryCancel')))
          .onPressed,
      isNull,
    );
    expect(calls, 1);
    saving.complete(false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('memorySave')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'detail retries failed image; only owner sees confirmed deletion',
    (tester) async {
      var loads = 0, deletes = 0, closed = 0;
      await _mount(
        tester,
        MemoryDetail(
          memory: _memory('one'),
          canDelete: true,
          loadPhoto: () async {
            if (++loads == 1) throw const MemoryFailure('unavailable');
            return _photo();
          },
          onDelete: () async {
            deletes++;
            return deletes > 1;
          },
          onClose: () => closed++,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'memoryPhotoRetry');
      expect(find.byKey(const Key('memoryFullPhoto')), findsOneWidget);
      expect(find.text('Намрын нар дулаахан байлаа.'), findsOneWidget);
      await _tap(tester, 'memoryDelete');
      expect(deletes, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('memoryConfirmDelete')));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(closed, 0);
      expect(find.byKey(const Key('memoryFullPhoto')), findsOneWidget);
      expect(find.text('Устгаж чадсангүй. Дахин оролдоорой.'), findsOneWidget);
      await _tap(tester, 'memoryDelete');
      await tester.tap(find.byKey(const Key('memoryConfirmDelete')));
      await tester.pumpAndSettle();
      expect(deletes, 2);
      expect(closed, 1);
    },
  );

  testWidgets('detail drops photo responses after the memory scope changes', (
    tester,
  ) async {
    final oldPhoto = Completer<Uint8List>();
    var closed = 0;
    Widget detail(SharedMemory memory, Future<Uint8List> Function() load) =>
        MemoryDetail(
          key: const Key('detail'),
          memory: memory,
          loadPhoto: load,
          canDelete: false,
          onDelete: () async => throw StateError('Partner cannot delete'),
          onClose: () => closed++,
        );
    await _mount(tester, detail(_memory('old'), () => oldPhoto.future));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SafeArea(
            child: detail(
              _memory('new'),
              () async => throw const MemoryFailure('not_found'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    oldPhoto.complete(_photo());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('memoryFullPhoto')), findsNothing);
    expect(find.byKey(const Key('memoryDelete')), findsNothing);
    await _tap(tester, 'memoryClose');
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'package:hamtdaa/wishes/wish_board.dart';
import 'package:hamtdaa/wishes/wish_controller.dart';
import 'package:hamtdaa/wishes/wish_models.dart';

import 'wish_fakes.dart';

const _capture = bool.fromEnvironment('CAPTURE_WISH_BOARD_UI');
final _now = DateTime.utc(2026, 10, 8, 20); // October 9 in Ulaanbaatar.

void main() {
  late WishFakeRepository repository;
  late WishController controller;
  late List<SharedWish> openedCalendar, addedMemory;

  SharedWish fromDraft(WishDraft draft) =>
      SharedWish.fromJson({...wishJson(), ...draft.toJson()});

  setUp(() {
    repository = WishFakeRepository();
    repository.onCreate = (_, _, draft) async => fromDraft(draft);
    controller = WishController(repository);
    openedCalendar = [];
    addedMemory = [];
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.bind(wishPair);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('wishCapture'),
          child: Scaffold(
            appBar: AppBar(title: const Text('Бид хоёр')),
            body: WishBoard(
              controller: controller,
              now: () => _now,
              onOpenCalendar: (wish) async => openedCalendar.add(wish),
              onAddMemory: (wish) async => addedMemory.add(wish),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(Key(key));
    await reveal(tester, finder);
    await tester.enterText(finder, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('empty title is rejected and back protects the unsaved draft', (
    tester,
  ) async {
    await mount(tester);
    await tapKey(tester, 'wishAdd');
    await tapKey(tester, 'wishSave');
    expect(repository.calls, isEmpty);
    await reveal(tester, find.byKey(const Key('wishTitle')));
    expect(find.text('Хүслээ бичээрэй.'), findsOneWidget);
    await enter(tester, 'wishTitle', 'Хамтдаа нэг өдөр аялъя');
    await tapKey(tester, 'wishBack');
    expect(find.text('Хүслээ хадгалахгүй гарах уу?'), findsOneWidget);
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('wishTitle')))
          .controller!
          .text,
      'Хамтдаа нэг өдөр аялъя',
    );
    await tapKey(tester, 'wishBack');
    await tapKey(tester, 'wishDiscard');
    expect(find.byKey(const Key('wishTitle')), findsNothing);
    expect(repository.calls, isEmpty);
    await tapKey(tester, 'wishAdd');
    await enter(tester, 'wishTitle', 'Нэг орой хамтдаа');
    await tapKey(tester, 'wishSave');
    expect(repository.calls.single.operation, 'create');
    expect(repository.calls.single.draft!.title, 'Нэг орой хамтдаа');
    expect(find.byKey(const Key('wishSave')), findsNothing);
    await reveal(tester, find.text('Нэг орой хамтдаа'));
    expect(find.text('Нэг орой хамтдаа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'both likes unlock scheduling and native selectors send Ulaanbaatar time',
    (tester) async {
      repository.rows = [wish(myLiked: false, partnerLiked: true, actor: 'b')];
      await mount(tester);
      await reveal(tester, find.byKey(Key('wishLike$wishId')));
      expect(find.byKey(Key('wishPlan$wishId')), findsNothing);
      expect(find.byKey(Key('wishDelete$wishId')), findsNothing);
      await tapKey(tester, 'wishLike$wishId');
      expect(repository.calls.single.liked, isTrue);
      await tapKey(tester, 'wishPlan$wishId');
      expect(find.text('2026-10-10'), findsOneWidget);
      await tapKey(tester, 'wishPlanDay');
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Сонгох'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'wishPlanTime');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Сонгох'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'wishConfirmPlan');
      expect(repository.calls.last.operation, 'plan');
      expect(repository.calls.last.starts, DateTime.utc(2026, 10, 10, 10));
      expect(openedCalendar, hasLength(1));
      expect(openedCalendar.single.eventStatus, 'pending');
      expect(
        openedCalendar.single.eventStartsAt,
        DateTime.utc(2026, 10, 10, 10),
      );
      expect(find.byKey(const Key('wishConfirmPlan')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only accepted past plans can finish and completed wishes offer a memory',
    (tester) async {
      repository.rows = [wish(status: 'planned', eventStatus: 'pending')];
      await mount(tester);
      await reveal(tester, find.byKey(Key('wishCalendar$wishId')));
      expect(find.byKey(Key('wishComplete$wishId')), findsNothing);
      repository.rows = [wish(status: 'planned', eventStatus: 'accepted')];
      await controller.refresh();
      await tester.pumpAndSettle();
      await tapKey(tester, 'wishComplete$wishId');
      expect(repository.calls.single.operation, 'complete');
      await tapKey(tester, 'wishFilterdone');
      await tapKey(tester, 'wishMemory$wishId');
      expect(addedMemory, hasLength(1));
      expect(addedMemory.single.isDone, isTrue);
      expect(addedMemory.single.eventStartsAt, DateTime.utc(2020, 1, 1, 10));
      expect(openedCalendar, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'suggestion prefills editable content and category filters the saved wish',
    (tester) async {
      repository.rows = [
        SharedWish.fromJson({
          ...wishJson(id: 'other-wish'),
          'title': 'Гэрийн тайван орой',
          'category': 'home',
        }),
      ];
      await mount(tester);
      await tapKey(tester, 'wishIdeas');
      await tapKey(tester, 'wishSuggestion0');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('wishTitle')))
            .controller!
            .text,
        'Хамтдаа пицца хийе',
      );
      await enter(tester, 'wishTitle', 'Бидний пиццаны орой');
      await tapKey(tester, 'wishSave');
      expect(repository.calls.single.draft!.category, 'food');
      expect(repository.calls.single.draft!.budget, 'low');
      expect(repository.calls.single.draft!.location, 'Гэртээ');
      await tapKey(tester, 'wishCategoryFilter');
      await tester.tap(find.text('Амттай зүйл').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(Key('wishCard$wishId')));
      expect(find.text('Бидний пиццаны орой'), findsOneWidget);
      expect(find.byKey(const Key('wishCardother-wish')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost create response locks the draft and retry recovers one saved wish',
    (tester) async {
      String? committedCommand;
      SharedWish? committed;
      var inserts = 0;
      repository.onCreate = (_, command, draft) async {
        if (committedCommand == command) return committed!;
        committedCommand = command;
        committed = fromDraft(draft);
        repository.rows = [committed!];
        inserts++;
        throw const WishFailure('unavailable');
      };
      await mount(tester);
      await tapKey(tester, 'wishAdd');
      await enter(tester, 'wishTitle', 'Нэг л удаа хадгалах хүсэл');
      await tapKey(tester, 'wishSave');
      expect(find.byKey(const Key('wishRetry')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('wishSave')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('wishSave')))
            .onPressed,
        isNull,
      );
      expect(repository.calls, hasLength(1));
      await tapKey(tester, 'wishRetry');
      expect(inserts, 1);
      expect(repository.calls, hasLength(2));
      expect(repository.calls[0].command, repository.calls[1].command);
      expect(controller.items, hasLength(1));
      expect(find.byKey(const Key('wishRetry')), findsNothing);
      expect(find.byKey(const Key('wishSave')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost plan response retry opens the existing calendar event once',
    (tester) async {
      repository.rows = [wish(partnerLiked: true)];
      var requests = 0;
      repository.onMutation = (operation, original, command) async {
        final planned = SharedWish.fromJson({
          ...wishJson(status: 'planned', partnerLiked: true, version: 2),
          'event_status': 'pending',
          'event_starts_at': '2026-10-10T10:00:00.000Z',
        });
        repository.rows = [planned];
        if (++requests == 1) throw const WishFailure('unavailable');
        return planned;
      };
      await mount(tester);
      await tapKey(tester, 'wishPlan$wishId');
      await tapKey(tester, 'wishConfirmPlan');
      expect(openedCalendar, isEmpty);
      await tapKey(tester, 'wishRetry');
      expect(repository.calls[0].command, repository.calls[1].command);
      expect(openedCalendar, hasLength(1));
      expect(openedCalendar.single.eventId, 'event-1');
      expect(find.byKey(const Key('wishConfirmPlan')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320-pixel screen supports large text in board editor and planner',
    (tester) async {
      repository.rows = [wish(partnerLiked: true)];
      await mount(tester, width: 320, scale: 1.5);
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'wishPlan$wishId');
      await reveal(tester, find.byKey(const Key('wishConfirmPlan')));
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'wishBack');
      await tapKey(tester, 'wishAdd');
      await enter(
        tester,
        'wishTitle',
        'Урт гарчигтай хамтдаа хийх сайхан зүйл',
      );
      await reveal(tester, find.byKey(const Key('wishBudget')));
      await reveal(tester, find.byKey(const Key('wishSave')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capture wishlist board for visual review', (tester) async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    repository.rows = [wish(partnerLiked: true)];
    await mount(tester);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('wishCapture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final output = File('verification/wishes-board.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  }, skip: !_capture);
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_screen.dart';
import 'package:hamtdaa/ui/theme.dart';
import 'together_fakes.dart';

void main() {
  late TogetherFakeRepository repository;
  late TogetherController controller;
  late CloudflareAuthRepository auth;
  setUp(() {
    repository = TogetherFakeRepository();
    controller = TogetherController(repository: repository, now: () => today);
    auth = CloudflareAuthRepository(transport: TogetherTransport(), storage: TogetherStorage());
  });
  tearDown(() async { controller.dispose(); await auth.dispose(); });
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: TogetherScreen(auth: auth, controller: controller)));
    await tester.pumpAndSettle();
  }
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('unpaired state explains mutual linking and offers no private features', (tester) async {
    repository.value = stateJson(paired: false);
    await mount(tester);
    expect(find.text('Хосоороо холбогдоорой'), findsOneWidget);
    expect(find.byKey(const Key('togetherCalendar')), findsNothing);
    expect(find.byKey(const Key('togetherAnswer')), findsNothing);
    expect(repository.commands, isEmpty);
  });

  testWidgets('owner creates with native selectors then edits and confirms deletion', (tester) async {
    await mount(tester);
    await tapKey(tester, 'togetherCreate');
    await tester.enterText(find.byKey(const Key('togetherTitle')), 'Хоёулаа кофе ууя');
    await tapKey(tester, 'togetherStartDate');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Сонгох'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'togetherStartTime');
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Сонгох'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('togetherLocation')), 'Кафе');
    await tester.enterText(find.byKey(const Key('togetherNote')), 'Цонхны хажууд');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tapKey(tester, 'togetherSaveEvent');
    expect(repository.commands.single.path, 'calendar/create');
    expect(repository.commands.single.body['starts_at'], '2026-10-06T10:00:00.000Z');
    expect(repository.commands.single.body['expected_pair_id'], pairId);
    await tapKey(tester, 'togetherEventevent-1');
    expect(find.text('Хоёулаа кофе ууя'), findsOneWidget);
    expect(find.byKey(const Key('togetherAccept')), findsNothing);
    await tapKey(tester, 'togetherEdit');
    await tester.enterText(find.byKey(const Key('togetherTitle')), 'Орой кофе ууя');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tapKey(tester, 'togetherSaveEvent');
    expect(repository.commands.last.body['expected_version'], 1);
    await tapKey(tester, 'togetherEventevent-1');
    expect(find.text('Орой кофе ууя'), findsOneWidget);
    await tapKey(tester, 'togetherDelete');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.commands, hasLength(2));
    await tester.tap(find.text('Устгах'));
    await tester.pumpAndSettle();
    expect(repository.commands.last.path, 'calendar/delete');
    expect(repository.commands.last.body['expected_version'], 2);
    expect(controller.data!.events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partner can accept and decline but cannot edit the owner event', (tester) async {
    repository.value = stateJson(events: [eventJson(creator: 'b')]);
    await mount(tester);
    await tapKey(tester, 'togetherEventevent-1');
    expect(find.byKey(const Key('togetherEdit')), findsNothing);
    expect(find.byKey(const Key('togetherDelete')), findsNothing);
    await tapKey(tester, 'togetherAccept');
    expect(find.text('Хоёулаа тохирсон'), findsOneWidget);
    expect(repository.commands.single.body['response'], 'accepted');
    await tapKey(tester, 'togetherDecline');
    expect(find.text('Татгалзсан'), findsOneWidget);
    expect(repository.commands.last.body['expected_version'], 2);
    expect(repository.commands.last.body['response'], 'declined');
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily flow confirms immutable answer then reveals both and loads history', (tester) async {
    repository.value = stateJson(daily: dailyJson(partner: 'Hidden before both'));
    await mount(tester);
    await tester.tap(find.text('Өдрийн асуулт'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden before both'), findsNothing);
    await tester.enterText(find.byKey(const Key('togetherAnswer')), 'Тэрэлжийн нэг өдөр');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tapKey(tester, 'togetherSubmitAnswer');
    expect(repository.commands, isEmpty);
    await tapKey(tester, 'togetherConfirmAnswer');
    expect(repository.commands.single.body['question_id'], 'dq-v1:2026-10-06:7');
    expect(find.text('Тэрэлжийн нэг өдөр'), findsOneWidget);
    expect(find.byKey(const Key('togetherAnswer')), findsNothing);
    expect(find.textContaining('Хосын хариултыг хүлээж байна'), findsOneWidget);
    repository.value = stateJson(daily: dailyJson(mine: 'Тэрэлжийн нэг өдөр', partner: 'Анхны уулзалт', both: true));
    await controller.refresh(quiet: true);
    await tester.pumpAndSettle();
    expect(find.text('Анхны уулзалт'), findsOneWidget);
    repository.historyValue = TogetherHistory([TogetherDaily.fromJson(dailyJson(mine: 'Өчигдөр', partner: 'Хамт', both: true, day: '2026-10-05'))], null);
    await tapKey(tester, 'togetherHistory');
    expect(controller.history, hasLength(1));
    await tester.ensureVisible(find.text('2026-10-05'));
    expect(find.text('Би: Өчигдөр'), findsOneWidget);
    expect(find.text('Хос: Хамт'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible polling stops in background and clears open detail after unlink', (tester) async {
    repository.value = stateJson(events: [eventJson()]);
    await mount(tester);
    await tapKey(tester, 'togetherEventevent-1');
    final initial = repository.months.length;
    // Platforms move through inactive before paused. Render the privacy cover
    // before paused disables frames, as the real lifecycle does.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 65));
    expect(repository.months.length, initial);
    expect(find.text('Кофе уух уу?'), findsNothing);
    repository.value = stateJson(paired: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Хосоороо холбогдоорой'), findsOneWidget);
    expect(find.text('Кофе уух уу?'), findsNothing);
    final resumed = repository.months.length;
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(repository.months.length, resumed + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month browse requests matching server month and day tap selects a day', (tester) async {
    await mount(tester);
    await tapKey(tester, 'togetherNextMonth');
    expect(repository.months.last, '2026-11');
    await tapKey(tester, 'togetherDay12');
    expect(controller.selectedDay, DateTime.utc(2026, 11, 12));
    expect(find.text('11 сарын 12'), findsOneWidget);
    await tapKey(tester, 'togetherPreviousMonth');
    expect(repository.months.last, '2026-10');
  });
}

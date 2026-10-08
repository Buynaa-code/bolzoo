import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/together/together_controller.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'together_fakes.dart';

void main() {
  late TogetherFakeRepository repository;
  late TogetherController controller;
  setUp(() { repository = TogetherFakeRepository(); controller = TogetherController(repository: repository, now: () => today); });
  tearDown(() => controller.dispose());

  test('ambiguous mutation retry retains its UUID and payload', () async {
    await controller.refresh();
    final command = controller.command('calendar/create', {'title': 'Кофе'})!;
    repository.onMutation = (_) async => throw const TogetherFailure('network_error', retryable: true);
    expect(await controller.send(command), isFalse);
    expect(controller.canMutate, isFalse);
    expect(controller.command('calendar/create', {'title': 'Өөр'}), isNull);
    repository.onMutation = (_) async {};
    expect(await controller.retry(), isTrue);
    expect(repository.commands, [same(command), same(command)]);
    expect(repository.commands.first.body['expected_pair_id'], pairId);
    expect(repository.commands.first.body['command_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(controller.pendingCommand, isNull);
  });

  test('retry never transfers an old-pair command to a new partner', () async {
    await controller.refresh();
    repository.onMutation = (_) async => throw const TogetherFailure('temporarily_unavailable', retryable: true);
    await controller.send(controller.command('daily/answer', {'question_id': 'q', 'answer': 'Private'})!);
    repository.value = stateJson(pair: otherPairId);
    expect(await controller.retry(), isFalse);
    expect(repository.commands, hasLength(1));
    expect(controller.pendingCommand, isNull);
    expect(controller.data!.pairId, otherPairId);
  });

  test('version conflict refreshes server data without silently reapplying edits', () async {
    repository.value = stateJson(events: [eventJson()]);
    await controller.refresh();
    repository.onMutation = (_) async {
      repository.value = stateJson(events: [eventJson(title: 'Шинэ нэр', version: 2)]);
      throw const TogetherFailure('conflict');
    };
    expect(await controller.send(controller.command('calendar/update', {'id': 'event-1', 'expected_version': 1})!), isFalse);
    expect(controller.event('event-1')!.title, 'Шинэ нэр');
    expect(controller.event('event-1')!.version, 2);
    expect(controller.failure!.code, 'conflict');
    expect(controller.pendingCommand, isNull);
  });

  test('late snapshot after auth switch never restores private data', () async {
    final response = Completer<TogetherSnapshot>();
    repository.onState = (_) => response.future;
    final loading = controller.refresh();
    repository.invalidate();
    response.complete(TogetherSnapshot.fromJson(stateJson(events: [eventJson()])));
    await loading;
    expect(controller.data, isNull);
    expect(controller.history, isEmpty);
    expect(controller.current, isFalse);
  });

  test('a stale month response cannot replace the newly selected month', () async {
    final first = Completer<TogetherSnapshot>();
    repository.onState = (month) async => month == '2026-10' ? first.future : TogetherSnapshot.fromJson(stateJson());
    final loading = controller.refresh();
    await controller.browseMonth(1);
    first.complete(TogetherSnapshot.fromJson(stateJson(events: [eventJson()])));
    await loading;
    expect(togetherMonth(controller.month), '2026-11');
    expect(controller.data!.events, isEmpty);
  });

  test('history is discarded when fresh pair check sees unlink', () async {
    await controller.refresh();
    repository.onHistory = (_) async {
      repository.value = stateJson(paired: false);
      return TogetherHistory([TogetherDaily.fromJson(dailyJson(mine: 'Private'))], null);
    };
    await controller.loadHistory();
    expect(controller.paired, isFalse);
    expect(controller.history, isEmpty);
    expect(controller.loadingHistory, isFalse);
  });

  test('unverified scope after polling network failure hides stale partner data', () async {
    repository.value = stateJson(events: [eventJson()]);
    await controller.refresh();
    repository.onState = (_) async => throw const TogetherFailure('network_error', retryable: true);
    await controller.refresh(quiet: true);
    expect(controller.data, isNull);
    expect(controller.canMutate, isFalse);
  });

  test('hidden partner answer stays hidden even if included in malformed response', () {
    final daily = TogetherDaily.fromJson(dailyJson(partner: 'Do not reveal'));
    expect(daily.partnerAnswer, isNull);
    expect(() => TogetherDaily.fromJson(dailyJson(partner: 'No own answer', both: true)), throwsFormatException);
  });

  test('calendar consistently uses UB midnight and multi-day overlap', () {
    final event = TogetherEvent.fromJson({...eventJson(),
      'starts_at': '2026-10-05T16:00:00.000Z', 'ends_at': '2026-10-06T16:00:00.000Z'});
    expect(event.start.hour, 0);
    expect(event.occursOn(DateTime.utc(2026, 10, 6)), isTrue);
    expect(event.occursOn(DateTime.utc(2026, 10, 7)), isFalse);
    expect(togetherUtc(DateTime(2026, 10, 6), 18, 0), DateTime.utc(2026, 10, 6, 10));
  });
}

import 'package:uuid/uuid.dart';

class TogetherFailure implements Exception {
  const TogetherFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  String get message => switch (code) {
    'unauthenticated' => 'Нэвтрэлт дууслаа. Дахин нэвтрээрэй.',
    'pair_required' || 'pair_changed' => 'Хосын холболт өөрчлөгдсөн байна.',
    'conflict' => 'Энэ болзоо өөрчлөгдсөн байна. Шинэ мэдээллийг шалгаад дахин оролдоорой.',
    'answer_locked' => 'Өнөөдрийн хариулт аль хэдийн хадгалагдсан байна.',
    'question_expired' => 'Өдөр солигдлоо. Өнөөдрийн шинэ асуултад хариулаарай.',
    'not_found' => 'Энэ болзоог устгасан эсвэл харах боломжгүй болсон байна.',
    'forbidden' => 'Энэ үйлдлийг хийх боломжгүй байна.',
    'quota_exceeded' => 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоорой.',
    'invalid_response' => 'Мэдээллийг баталгаажуулж чадсангүй. Дахин шалгаарай.',
    'network_error' || 'temporarily_unavailable' =>
      'Холболт түр тасарлаа. Дахин оролдоорой.',
    _ => 'Үйлдлийг хийж чадсангүй. Оруулсан мэдээллээ шалгаарай.',
  };
}

String _string(Object? value) {
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

String _text(Object? value) {
  if (value is! String) throw const FormatException();
  return value;
}

DateTime _utc(Object? value) {
  final parsed = DateTime.parse(_string(value));
  if (!parsed.isUtc) throw const FormatException();
  return parsed;
}

/// Shared calendar and daily questions use the same Ulaanbaatar day on both phones.
DateTime togetherTime(DateTime utc) => utc.toUtc().add(const Duration(hours: 8));
DateTime togetherUtc(DateTime day, int hour, int minute) =>
    DateTime.utc(day.year, day.month, day.day, hour, minute)
        .subtract(const Duration(hours: 8));
String togetherMonth(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';
String togetherDay(DateTime date) =>
    '${togetherMonth(date)}-${date.day.toString().padLeft(2, '0')}';
String togetherClock(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String? togetherTextError(String? value, int limit) {
  final text = value?.trim() ?? '';
  if (text.length > limit) return 'Текстээ бага зэрэг богиносгоорой.';
  if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(text)) {
    return 'Текстэд танигдахгүй тэмдэгт байна.';
  }
  return null;
}

enum TogetherEventStatus {
  pending, accepted, declined;
  String get label => switch (this) {
    pending => 'Хариу хүлээж байна',
    accepted => 'Хоёулаа тохирсон',
    declined => 'Татгалзсан',
  };
}

class TogetherEvent {
  const TogetherEvent({required this.id, required this.title, required this.note,
    required this.location, required this.startsAt, required this.endsAt,
    required this.creatorId, required this.status, required this.version});
  final String id, title, note, location, creatorId;
  final DateTime startsAt;
  final DateTime? endsAt;
  final TogetherEventStatus status;
  final int version;
  DateTime get start => togetherTime(startsAt);
  DateTime? get end => endsAt == null ? null : togetherTime(endsAt!);
  bool occursOn(DateTime day) {
    final lower = togetherUtc(day, 0, 0);
    final upper = lower.add(const Duration(days: 1));
    return startsAt.isBefore(upper) &&
        (endsAt == null ? !startsAt.isBefore(lower) : endsAt!.isAfter(lower));
  }
  factory TogetherEvent.fromJson(Map<String, dynamic> value) {
    final version = value['version'];
    if (version is! int || version < 1) throw const FormatException();
    final start = _utc(value['starts_at']);
    final end = value['ends_at'] == null ? null : _utc(value['ends_at']);
    if (end != null && !end.isAfter(start)) throw const FormatException();
    return TogetherEvent(id: _string(value['id']), title: _string(value['title']),
      note: _text(value['note']), location: _text(value['location']),
      startsAt: start, endsAt: end, creatorId: _string(value['creator_id']),
      status: TogetherEventStatus.values.byName(_string(value['status'])), version: version);
  }
}

class TogetherDaily {
  const TogetherDaily({required this.day, required this.questionId,
    required this.question, required this.myAnswer, required this.partnerAnswer,
    required this.bothAnswered});
  final String day, questionId, question;
  final String? myAnswer, partnerAnswer;
  final bool bothAnswered;
  factory TogetherDaily.fromJson(Map<String, dynamic> value) {
    final day = _string(value['day']);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) || value['both_answered'] is! bool) {
      throw const FormatException();
    }
    final both = value['both_answered'] as bool;
    final mine = value['my_answer'] == null ? null : _text(value['my_answer']);
    final partner = both ? _text(value['partner_answer']) : null;
    if (both && mine == null) throw const FormatException();
    return TogetherDaily(day: day, questionId: _string(value['question_id']),
      question: _string(value['question']), myAnswer: mine,
      partnerAnswer: partner, bothAnswered: both);
  }
}

class TogetherSnapshot {
  const TogetherSnapshot({required this.paired, this.pairId, this.partnerId,
    this.partnerName, this.events = const [], this.daily});
  final bool paired;
  final String? pairId, partnerId, partnerName;
  final List<TogetherEvent> events;
  final TogetherDaily? daily;
  factory TogetherSnapshot.fromJson(Map<String, dynamic> value) {
    if (value['paired'] == false) return const TogetherSnapshot(paired: false);
    if (value['paired'] != true || value['partner'] is! Map || value['events'] is! List) {
      throw const FormatException();
    }
    final partner = Map<String, dynamic>.from(value['partner'] as Map);
    return TogetherSnapshot(paired: true, pairId: _string(value['pair_id']),
      partnerId: _string(partner['id']),
      partnerName: partner['display_name'] == null ? null : _text(partner['display_name']),
      events: List.unmodifiable((value['events'] as List).map((e) =>
          TogetherEvent.fromJson(Map<String, dynamic>.from(e as Map)))),
      daily: value['daily'] == null ? null : TogetherDaily.fromJson(
          Map<String, dynamic>.from(value['daily'] as Map)));
  }
}

class TogetherHistory {
  const TogetherHistory(this.entries, this.nextBeforeDay);
  final List<TogetherDaily> entries;
  final String? nextBeforeDay;
  factory TogetherHistory.fromJson(Map<String, dynamic> value) {
    final cursor = value['next_before_day'];
    if (value['entries'] is! List || (cursor != null &&
        (cursor is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(cursor)))) {
      throw const FormatException();
    }
    return TogetherHistory(List.unmodifiable((value['entries'] as List).map((e) =>
      TogetherDaily.fromJson(Map<String, dynamic>.from(e as Map)))), cursor as String?);
  }
}

class TogetherCommand {
  TogetherCommand(this.path, String pairId, Map<String, dynamic> fields)
      : body = Map.unmodifiable({...fields, 'command_id': const Uuid().v4(),
          'expected_pair_id': pairId});
  final String path;
  final Map<String, dynamic> body;
  String get pairId => body['expected_pair_id'] as String;
}

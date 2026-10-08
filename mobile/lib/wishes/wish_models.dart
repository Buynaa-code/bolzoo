/// Values accepted by the shared wishlist API. Keep unknown server values out
/// of the UI instead of treating them as a valid state.
const wishCategories = ['home', 'outdoor', 'food', 'travel', 'other'];
const wishBudgets = ['free', 'low', 'medium', 'high'];
const wishStatuses = ['idea', 'planned', 'done'];

final class SharedWish {
  const SharedWish({
    required this.id,
    required this.pairId,
    required this.creatorId,
    required this.title,
    required this.note,
    required this.location,
    required this.category,
    required this.budget,
    required this.status,
    required this.version,
    required this.myLiked,
    required this.partnerLiked,
    required this.createdAt,
    required this.updatedAt,
    this.eventId,
    this.eventStartsAt,
    this.eventStatus,
  });

  final String id, pairId, creatorId, title, note, location;
  final String category, budget, status;
  final int version;
  final bool myLiked, partnerLiked;
  final String? eventId;
  final DateTime? eventStartsAt;
  final String? eventStatus;
  final DateTime createdAt, updatedAt;

  bool get bothLiked => myLiked && partnerLiked;
  bool get isIdea => status == 'idea';
  bool get isPlanned => status == 'planned';
  bool get isDone => status == 'done';
  bool get canPlan => isIdea && bothLiked;
  bool canCompleteAt(DateTime now) =>
      isPlanned &&
      eventStatus == 'accepted' &&
      eventStartsAt != null &&
      !eventStartsAt!.isAfter(now);
  bool get canComplete => canCompleteAt(DateTime.now());

  factory SharedWish.fromJson(Map<String, dynamic> json) {
    final status = _choice(json, 'status', wishStatuses);
    final event = json['event_id'];
    if (!json.containsKey('event_id') ||
        (event != null && !_validId(event)) ||
        (status == 'idea' && event != null) ||
        (status == 'planned' && event == null)) {
      throw const FormatException('Invalid wish event');
    }
    final version = json['version'];
    if (version is! int ||
        version < 1 ||
        version > 9007199254740991 ||
        json['my_liked'] is! bool ||
        json['partner_liked'] is! bool) {
      throw const FormatException('Invalid wish state');
    }
    final created = _timestamp(json, 'created_at');
    final updated = _timestamp(json, 'updated_at');
    final eventStatus = json['event_status'];
    final starts = json['event_starts_at'];
    if (!json.containsKey('event_status') ||
        !json.containsKey('event_starts_at') ||
        (eventStatus != null &&
            !const ['pending', 'accepted', 'declined'].contains(eventStatus)) ||
        (event == null && (eventStatus != null || starts != null)) ||
        (event != null && (eventStatus == null || starts == null))) {
      throw const FormatException('Invalid linked event');
    }
    if (updated.isBefore(created)) {
      throw const FormatException('Invalid wish chronology');
    }
    return SharedWish(
      id: _id(json, 'id'),
      pairId: _id(json, 'pair_id'),
      creatorId: _id(json, 'creator_id'),
      title: _text(json, 'title', 80, required: true),
      note: _text(json, 'note', 500),
      location: _text(json, 'location', 120),
      category: _choice(json, 'category', wishCategories),
      budget: _choice(json, 'budget', wishBudgets),
      status: status,
      version: version,
      myLiked: json['my_liked'] as bool,
      partnerLiked: json['partner_liked'] as bool,
      eventId: event as String?,
      eventStatus: eventStatus as String?,
      eventStartsAt: starts == null
          ? null
          : _timestamp(json, 'event_starts_at'),
      createdAt: created,
      updatedAt: updated,
    );
  }
}

final class WishDraft {
  const WishDraft({
    required this.title,
    this.note = '',
    this.location = '',
    this.category = 'other',
    this.budget = 'free',
  });

  final String title, note, location, category, budget;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'title': title.trim(),
      'note': note.trim(),
      'location': location.trim(),
      'category': category,
      'budget': budget,
    };
    try {
      _text(result, 'title', 80, required: true);
      _text(result, 'note', 500);
      _text(result, 'location', 120);
      _choice(result, 'category', wishCategories);
      _choice(result, 'budget', wishBudgets);
    } on FormatException {
      throw const WishFailure('invalid_input');
    }
    return result;
  }
}

/// The export deliberately has no partner's like state. Metadata is restricted
/// to wishes authored by the requesting account; likes may refer to other wishes.
final class WishExport {
  WishExport({
    required List<Map<String, dynamic>> wishes,
    required List<String> likedWishIds,
  }) : wishes = List.unmodifiable(
         wishes.map((value) => Map<String, dynamic>.unmodifiable(value)),
       ),
       likedWishIds = List.unmodifiable(likedWishIds);
  final List<Map<String, dynamic>> wishes;
  final List<String> likedWishIds;

  factory WishExport.fromJson(
    Map<String, dynamic> value, {
    required String pairId,
    required String actorId,
  }) {
    try {
      if (value['ok'] != true || value['pair_id'] != pairId) {
        throw const FormatException();
      }
      final rows = value['wishes'] as List;
      final likes = value['likes'] as List;
      if (rows.length > 500 || likes.length > 500) {
        throw const FormatException();
      }
      final own = <Map<String, dynamic>>[];
      for (final row in rows) {
        final json = Map<String, dynamic>.from(row as Map);
        if (json.containsKey('partner_liked')) throw const FormatException();
        final wish = SharedWish.fromJson({...json, 'partner_liked': false});
        if (wish.pairId != pairId || wish.creatorId != actorId) {
          throw const FormatException();
        }
        // Whitelist the schema rather than retaining arbitrary server fields.
        own.add({
          for (final key in const [
            'id',
            'pair_id',
            'creator_id',
            'title',
            'note',
            'location',
            'category',
            'budget',
            'status',
            'version',
            'my_liked',
            'event_id',
            'event_starts_at',
            'event_status',
            'created_at',
            'updated_at',
          ])
            key: json[key],
        });
      }
      final likedIds = <String>[];
      for (final row in likes) {
        if (row is! Map || row['liked'] != true || !_validId(row['wish_id'])) {
          throw const FormatException();
        }
        likedIds.add(row['wish_id'] as String);
      }
      if (own.map((row) => row['id']).toSet().length != own.length ||
          likedIds.toSet().length != likedIds.length) {
        throw const FormatException();
      }
      return WishExport(wishes: own, likedWishIds: likedIds);
    } catch (_) {
      throw const FormatException('Invalid wishlist export');
    }
  }

  Map<String, dynamic> toJson() => {
    'wishes': wishes,
    'likes': [
      for (final id in likedWishIds) {'wish_id': id, 'liked': true},
    ],
  };
}

final class WishFailure implements Exception {
  const WishFailure(this.code, {this.outcomeUnknown = false});
  final String code;
  final bool outcomeUnknown;

  bool get needsRetry =>
      outcomeUnknown ||
      const {
        'unavailable',
        'temporarily_unavailable',
        'network_error',
        'invalid_response',
        'timeout',
        'command_in_progress',
      }.contains(code);
  bool get invalidatesScope => const {
    'unauthenticated',
    'pair_changed',
    'pair_required',
    'forbidden',
  }.contains(code);

  String get message => switch (code) {
    'feature_unavailable' =>
      'Хүслийн самбарын үйлчилгээ хараахан нээгдээгүй байна. Түр хүлээгээд дахин шалгаарай.',
    'unauthenticated' => 'Нэвтрэлт дууслаа. Дахин нэвтрээрэй.',
    'pair_changed' ||
    'pair_required' ||
    'forbidden' => 'Хосын холболт өөрчлөгдсөн байна.',
    'version_conflict' || 'conflict' || 'stale_version' =>
      'Энэ хүсэл шинэчлэгдсэн байна. Шинэ мэдээллийг шалгаад дахин оролдоорой.',
    'not_found' ||
    'wish_deleted' => 'Энэ хүсэл устсан эсвэл харах боломжгүй болсон байна.',
    'event_deleted' =>
      'Төлөвлөсөн уулзалт устсан байна. Хүслээ дахин төлөвлөж болно.',
    'creator_only' => 'Зөвхөн өөрийн нэмсэн хүслийг устгах боломжтой.',
    'both_likes_required' ||
    'both_required' ||
    'mutual_like_required' => 'Хоёулаа зүрх дарсны дараа төлөвлөж болно.',
    'invalid_status' ||
    'already_planned' => 'Хүслийн төлөв өөрчлөгдсөн байна. Дахин шалгаарай.',
    'quota_exceeded' =>
      'Хадгалах эсвэл өнөөдрийн үйлдлийн хязгаарт хүрлээ. Түр хүлээгээд дахин оролдоорой.',
    'invalid_input' ||
    'invalid_request' ||
    'validation' => 'Гарчиг болон оруулсан мэдээллээ шалгаарай.',
    'invalid_dates' => 'Төлөвлөх огноо, дуусах цагаа шалгаарай.',
    'pending_command' =>
      'Өмнөх үйлдлийн хариу тодорхойгүй байна. Дахин оролдоод баталгаажуулаарай.',
    'rate_limited' => 'Түр хүлээгээд дахин оролдоорой.',
    _ =>
      'Хүсэлд оруулсан өөрчлөлтийг баталгаажуулж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
  };
}

bool _validId(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

String _id(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (!_validId(value)) throw const FormatException('Invalid identifier');
  return value as String;
}

String _text(
  Map<String, dynamic> json,
  String key,
  int maximum, {
  bool required = false,
}) {
  final value = json[key];
  if (value is! String ||
      value.length > maximum ||
      RegExp(
        r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
      ).hasMatch(value) ||
      (required && value.trim().isEmpty)) {
    throw const FormatException('Invalid wish text');
  }
  return value;
}

String _choice(Map<String, dynamic> json, String key, List<String> choices) {
  final value = json[key];
  if (value is! String || !choices.contains(value)) {
    throw const FormatException('Unknown wish value');
  }
  return value;
}

DateTime _timestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid timestamp');
  }
  final parsed = DateTime.parse(value);
  // DateTime.parse otherwise normalizes invalid dates such as February 31.
  if (!parsed.toIso8601String().startsWith(value.substring(0, 19))) {
    throw const FormatException('Invalid timestamp');
  }
  return parsed;
}

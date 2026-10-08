import 'dart:math';
import 'gift_models.dart';
export 'gift_models.dart';

const _notProvided = Object();
final _random = Random.secure();

/// An opaque ID for records created on this device, without a backend dependency.
String newLocalId() {
  final entropy = List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$entropy';
}

/// Keeps the chosen wall-clock components; no UTC conversion is performed.
DateTime localDateTime(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);

DateTime localCalendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class UserProfile {
  const UserProfile({this.name = '', this.togetherSince});

  final String name;
  final DateTime? togetherSince;

  UserProfile copyWith({String? name, Object? togetherSince = _notProvided}) =>
      UserProfile(
        name: name ?? this.name,
        togetherSince: identical(togetherSince, _notProvided)
            ? this.togetherSince
            : togetherSince as DateTime?,
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'togetherSince': togetherSince == null ? null : _encodeDay(togetherSince!),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: _optionalString(json, 'name') ?? '',
    togetherSince: _optionalDay(json, 'togetherSince'),
  );
}

class DateEvent {
  const DateEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.createdAt,
    this.place = '',
    this.note = '',
    this.shared = false,
    this.reminderMinutes = 0,
    this.templateId = 'coffee',
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime createdAt;
  final String place;
  final String note;
  final bool shared;
  final int reminderMinutes;
  final String templateId;

  DateEvent copyWith({
    String? id,
    String? title,
    DateTime? startsAt,
    DateTime? createdAt,
    String? place,
    String? note,
    bool? shared,
    int? reminderMinutes,
    String? templateId,
  }) => DateEvent(
    id: id ?? this.id,
    title: title ?? this.title,
    startsAt: startsAt ?? this.startsAt,
    createdAt: createdAt ?? this.createdAt,
    place: place ?? this.place,
    note: note ?? this.note,
    shared: shared ?? this.shared,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    templateId: templateId ?? this.templateId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'startsAt': localDateTime(startsAt).toIso8601String(),
    'createdAt': localDateTime(createdAt).toIso8601String(),
    'place': place,
    'note': note,
    'shared': shared,
    'reminderMinutes': reminderMinutes,
    'templateId': templateId,
  };

  factory DateEvent.fromJson(Map<String, dynamic> json) => DateEvent(
    id: _requiredNonBlankString(json, 'id'),
    title: _requiredNonBlankString(json, 'title'),
    startsAt: _requiredDateTime(json, 'startsAt'),
    createdAt: _requiredDateTime(json, 'createdAt'),
    place: _optionalString(json, 'place') ?? '',
    note: _optionalString(json, 'note') ?? '',
    shared: json['shared'] == true,
    reminderMinutes: json['reminderMinutes'] is int
        ? json['reminderMinutes'] as int
        : 0,
    templateId: _optionalString(json, 'templateId') ?? 'coffee',
  );
}

class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.title,
    required this.date,
    this.text = '',
    this.photoPath,
    this.eventId,
    this.place = '',
    this.placeId,
    this.shared = false,
    this.likedByMe = false,
    this.likeCount = 0,
    this.comments = const [],
    this.mediaKey,
  });

  final String id;
  final String title;
  final DateTime date;
  final String text;
  final String? photoPath;
  final String? eventId;
  final String place;
  final String? placeId, mediaKey;
  final bool shared, likedByMe;
  final int likeCount;
  final List<MemoryComment> comments;

  MemoryEntry copyWith({
    String? id,
    String? title,
    DateTime? date,
    String? text,
    Object? photoPath = _notProvided,
    Object? eventId = _notProvided,
    String? place,
    Object? placeId = _notProvided,
    bool? shared,
    bool? likedByMe,
    int? likeCount,
    List<MemoryComment>? comments,
    Object? mediaKey = _notProvided,
  }) => MemoryEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    date: date ?? this.date,
    text: text ?? this.text,
    photoPath: identical(photoPath, _notProvided)
        ? this.photoPath
        : photoPath as String?,
    eventId: identical(eventId, _notProvided)
        ? this.eventId
        : eventId as String?,
    place: place ?? this.place,
    placeId: identical(placeId, _notProvided)
        ? this.placeId
        : placeId as String?,
    mediaKey: identical(mediaKey, _notProvided)
        ? this.mediaKey
        : mediaKey as String?,
    shared: shared ?? this.shared,
    likedByMe: likedByMe ?? this.likedByMe,
    likeCount: likeCount ?? this.likeCount,
    comments: List.unmodifiable(comments ?? this.comments),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'date': _encodeDay(date),
    'text': text,
    'photoPath': photoPath,
    'eventId': eventId,
    'place': place,
    'placeId': placeId,
    'mediaKey': mediaKey,
    'shared': shared,
    'likedByMe': likedByMe,
    'likeCount': likeCount,
    'comments': comments.map((c) => c.toJson()).toList(),
  };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
    id: _requiredNonBlankString(json, 'id'),
    title: _requiredNonBlankString(json, 'title'),
    date: _requiredDay(json, 'date'),
    text: _optionalString(json, 'text') ?? '',
    photoPath: _optionalString(json, 'photoPath'),
    eventId: _optionalString(json, 'eventId'),
    place: _optionalString(json, 'place') ?? '',
    placeId: _optionalString(json, 'placeId'),
    mediaKey: _optionalString(json, 'mediaKey'),
    shared: json['shared'] == true,
    likedByMe: json['likedByMe'] == true,
    likeCount: json['likeCount'] is int ? json['likeCount'] as int : 0,
    comments: List.unmodifiable(
      _requiredObjectList(
        json['comments'] ?? [],
        'comments',
      ).map(MemoryComment.fromJson),
    ),
  );
}

class MemoryComment {
  const MemoryComment({
    required this.id,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });
  final String id, authorName, text;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'authorName': authorName,
    'text': text,
    'createdAt': localDateTime(createdAt).toIso8601String(),
  };
  factory MemoryComment.fromJson(Map<String, dynamic> j) => MemoryComment(
    id: _requiredNonBlankString(j, 'id'),
    authorName: _requiredNonBlankString(j, 'authorName'),
    text: _requiredNonBlankString(j, 'text'),
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
  );
}

class PlaceEntry {
  const PlaceEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.address = '',
    this.note = '',
    this.latitude,
    this.longitude,
    this.category = 'other',
    this.shared = false,
  });
  final String id, name, address, note, category;
  final DateTime createdAt;
  final double? latitude, longitude;
  final bool shared;
  PlaceEntry copyWith({
    String? name,
    String? address,
    String? note,
    double? latitude,
    double? longitude,
    String? category,
    bool? shared,
  }) => PlaceEntry(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    address: address ?? this.address,
    note: note ?? this.note,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    category: category ?? this.category,
    shared: shared ?? this.shared,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': localDateTime(createdAt).toIso8601String(),
    'address': address,
    'note': note,
    'category': category,
    'shared': shared,
    'latitude': latitude,
    'longitude': longitude,
  };
  factory PlaceEntry.fromJson(Map<String, dynamic> j) {
    final lat = (j['latitude'] as num?)?.toDouble();
    final lon = (j['longitude'] as num?)?.toDouble();
    if ((lat == null) != (lon == null) ||
        (lat != null &&
            (!lat.isFinite ||
                lat < -90 ||
                lat > 90 ||
                !lon!.isFinite ||
                lon < -180 ||
                lon > 180)))
      throw const FormatException('Invalid coordinates');
    return PlaceEntry(
      id: _requiredNonBlankString(j, 'id'),
      name: _requiredNonBlankString(j, 'name'),
      createdAt: _requiredDateTime(j, 'createdAt'),
      address: _optionalString(j, 'address') ?? '',
      note: _optionalString(j, 'note') ?? '',
      category: _optionalString(j, 'category') ?? 'other',
      shared: j['shared'] == true,
      latitude: lat,
      longitude: lon,
    );
  }
}

class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.kind,
    required this.sourceId,
    this.read = false,
  });
  final String id, title, body, kind, sourceId;
  final DateTime createdAt;
  final bool read;
  AppNotice copyWith({bool? read}) => AppNotice(
    id: id,
    title: title,
    body: body,
    createdAt: createdAt,
    kind: kind,
    sourceId: sourceId,
    read: read ?? this.read,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': localDateTime(createdAt).toIso8601String(),
    'kind': kind,
    'sourceId': sourceId,
    'read': read,
  };
  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
    id: _requiredNonBlankString(j, 'id'),
    title: _requiredNonBlankString(j, 'title'),
    body: _optionalString(j, 'body') ?? '',
    createdAt: _requiredDateTime(j, 'createdAt'),
    kind: _requiredNonBlankString(j, 'kind'),
    sourceId: _optionalString(j, 'sourceId') ?? '',
    read: j['read'] == true,
  );
}

class AppData {
  AppData({
    this.profile = const UserProfile(),
    List<DateEvent> events = const [],
    List<MemoryEntry> memories = const [],
    List<PlaceEntry> places = const [],
    List<AppNotice> notices = const [],
    this.gifts = const GiftData.empty(),
  }) : events = List.unmodifiable(events),
       memories = List.unmodifiable(memories),
       places = List.unmodifiable(places),
       notices = List.unmodifiable(notices) {
    _ensureUniqueIds(this.events.map((event) => event.id), 'events');
    _ensureUniqueIds(this.memories.map((memory) => memory.id), 'memories');
    _ensureUniqueIds(this.places.map((place) => place.id), 'places');
    _ensureUniqueIds(this.notices.map((notice) => notice.id), 'notices');
  }

  static const schemaVersion = 2;

  final UserProfile profile;
  final List<DateEvent> events;
  final List<MemoryEntry> memories;
  final List<PlaceEntry> places;
  final List<AppNotice> notices;
  final GiftData gifts;

  AppData copyWith({
    UserProfile? profile,
    List<DateEvent>? events,
    List<MemoryEntry>? memories,
    List<PlaceEntry>? places,
    List<AppNotice>? notices,
    GiftData? gifts,
  }) => AppData(
    profile: profile ?? this.profile,
    events: events ?? this.events,
    memories: memories ?? this.memories,
    places: places ?? this.places,
    notices: notices ?? this.notices,
    gifts: gifts ?? this.gifts,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'profile': profile.toJson(),
    'events': events.map((event) => event.toJson()).toList(),
    'memories': memories.map((memory) => memory.toJson()).toList(),
    'places': places.map((place) => place.toJson()).toList(),
    'notices': notices.map((notice) => notice.toJson()).toList(),
    'gifts': gifts.toJson(),
  };

  factory AppData.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion && json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported app data schema version.');
    }
    final profile = _requiredObject(json['profile'], 'profile');
    final events = _requiredObjectList(
      json['events'],
      'events',
    ).map(DateEvent.fromJson).toList();
    final memories = _requiredObjectList(
      json['memories'],
      'memories',
    ).map(MemoryEntry.fromJson).toList();
    final eventIds = events.map((event) => event.id).toSet();
    for (final memory in memories) {
      if (memory.eventId != null && !eventIds.contains(memory.eventId)) {
        throw const FormatException('A memory references a missing event.');
      }
    }
    return AppData(
      profile: UserProfile.fromJson(profile),
      events: events,
      memories: memories,
      places: _requiredObjectList(
        json['places'] ?? [],
        'places',
      ).map(PlaceEntry.fromJson).toList(),
      notices: _requiredObjectList(
        json['notices'] ?? [],
        'notices',
      ).map(AppNotice.fromJson).toList(),
      gifts: json['gifts'] == null
          ? const GiftData.empty()
          : GiftData.fromJson(_requiredObject(json['gifts'], 'gifts')),
    );
  }
}

void _ensureUniqueIds(Iterable<String> ids, String collection) {
  final seen = <String>{};
  for (final id in ids) {
    if (id.trim().isEmpty || !seen.add(id)) {
      throw FormatException('Invalid or duplicate record ID in $collection.');
    }
  }
}

String _encodeDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('$key must be a string.');
}

String _requiredNonBlankString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json, key);
  if (value == null || value.trim().isEmpty) {
    throw FormatException('$key must not be empty.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final text = _requiredNonBlankString(json, key);
  // Offset-free values intentionally retain the user's chosen local time.
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?$',
  ).hasMatch(text)) {
    throw FormatException('$key must be a local date and time.');
  }
  final result = DateTime.tryParse(text);
  if (result == null ||
      localDateTime(result).toIso8601String() != _canonicalIso(text)) {
    throw FormatException('$key contains an invalid date and time.');
  }
  return result;
}

String _canonicalIso(String text) {
  final parts = text.split('.');
  if (parts.length == 1) return '${parts[0]}.000';
  final fraction = parts[1].padRight(6, '0');
  return '${parts[0]}.${fraction.endsWith('000') ? fraction.substring(0, 3) : fraction}';
}

DateTime _requiredDay(Map<String, dynamic> json, String key) {
  final text = _requiredNonBlankString(json, key);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw FormatException('$key must be a calendar date.');
  }
  final result = DateTime.tryParse(text);
  if (result == null || _encodeDay(result) != text) {
    throw FormatException('$key contains an invalid calendar date.');
  }
  return localCalendarDay(result);
}

DateTime? _optionalDay(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _requiredDay(json, key);

Map<String, dynamic> _requiredObject(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field must be an object.');
}

List<Map<String, dynamic>> _requiredObjectList(Object? value, String field) {
  if (value is! List) throw FormatException('$field must be a list.');
  return value.map((item) => _requiredObject(item, field)).toList();
}

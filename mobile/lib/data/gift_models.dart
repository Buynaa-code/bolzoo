import 'models.dart' show localDateTime;

enum InvitationState { draft, pending, accepted, proposed, cancelled }

enum InvitationResponse { accept, propose }

class DateInvitation {
  const DateInvitation({
    required this.id,
    required this.templateId,
    required this.title,
    required this.recipientName,
    required this.senderName,
    required this.startsAt,
    required this.createdAt,
    this.place = '',
    this.message = '',
    this.state = InvitationState.draft,
    this.creatorId,
    this.recipientId,
    this.version = 1,
    this.proposedAt,
    this.shareUrl,
  });

  final String id, templateId, title, recipientName, senderName, place, message;
  final DateTime startsAt, createdAt;
  final InvitationState state;
  final String? creatorId, recipientId, shareUrl;
  final int version;
  final DateTime? proposedAt;

  DateInvitation copyWith({
    String? id, String? templateId, String? title, String? recipientName,
    String? senderName, DateTime? startsAt, String? place, String? message,
    InvitationState? state, String? creatorId, String? recipientId,
    int? version, DateTime? proposedAt, String? shareUrl,
  }) => DateInvitation(
    id: id ?? this.id, templateId: templateId ?? this.templateId,
    title: title ?? this.title, recipientName: recipientName ?? this.recipientName,
    senderName: senderName ?? this.senderName, startsAt: startsAt ?? this.startsAt,
    createdAt: createdAt, place: place ?? this.place, message: message ?? this.message,
    state: state ?? this.state, creatorId: creatorId ?? this.creatorId,
    recipientId: recipientId ?? this.recipientId, version: version ?? this.version,
    proposedAt: proposedAt ?? this.proposedAt, shareUrl: shareUrl ?? this.shareUrl,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'templateId': templateId, 'title': title,
    'recipientName': recipientName, 'senderName': senderName,
    'startsAt': localDateTime(startsAt).toIso8601String(),
    'createdAt': localDateTime(createdAt).toIso8601String(),
    'place': place, 'message': message, 'state': state.name,
    'creatorId': creatorId, 'recipientId': recipientId, 'version': version,
    'proposedAt': proposedAt == null ? null : localDateTime(proposedAt!).toIso8601String(),
    'shareUrl': shareUrl,
  };

  factory DateInvitation.fromJson(Map<String, dynamic> json) => DateInvitation(
    id: _text(json, 'id'), templateId: _text(json, 'templateId'),
    title: _text(json, 'title'), recipientName: _text(json, 'recipientName'),
    senderName: _text(json, 'senderName'), startsAt: _date(json, 'startsAt'),
    createdAt: _date(json, 'createdAt'), place: _text(json, 'place', blank: true),
    message: _text(json, 'message', blank: true),
    state: InvitationState.values.firstWhere((state) => state.name == json['state'],
      orElse: () => throw const FormatException('Unknown invitation state.')),
    creatorId: _nullableText(json, 'creatorId'),
    recipientId: _nullableText(json, 'recipientId'),
    version: _version(json['version']),
    proposedAt: json['proposedAt'] == null ? null : _date(json, 'proposedAt'),
    shareUrl: _nullableText(json, 'shareUrl'),
  );
}

class FlowerGreeting {
  const FlowerGreeting({
    required this.id, required this.templateId, required this.colorId,
    required this.occasion, required this.recipientName, required this.senderName,
    required this.message, required this.createdAt, this.memoryId,
  });
  final String id, templateId, colorId, occasion, recipientName, senderName, message;
  final DateTime createdAt;
  final String? memoryId;

  FlowerGreeting copyWith({String? memoryId}) => FlowerGreeting(
    id: id, templateId: templateId, colorId: colorId, occasion: occasion,
    recipientName: recipientName, senderName: senderName, message: message,
    createdAt: createdAt, memoryId: memoryId ?? this.memoryId,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'templateId': templateId, 'colorId': colorId, 'occasion': occasion,
    'recipientName': recipientName, 'senderName': senderName, 'message': message,
    'createdAt': localDateTime(createdAt).toIso8601String(), 'memoryId': memoryId,
  };
  factory FlowerGreeting.fromJson(Map<String, dynamic> json) => FlowerGreeting(
    id: _text(json, 'id'), templateId: _text(json, 'templateId'),
    colorId: _text(json, 'colorId'), occasion: _text(json, 'occasion'),
    recipientName: _text(json, 'recipientName'), senderName: _text(json, 'senderName'),
    message: _text(json, 'message'), createdAt: _date(json, 'createdAt'),
    memoryId: _nullableText(json, 'memoryId'),
  );
}

class GiftData {
  const GiftData.empty()
    : invitations = const [], greetings = const [], favoriteIdeaIds = const [];
  GiftData({List<DateInvitation> invitations = const [],
    List<FlowerGreeting> greetings = const [], List<String> favoriteIdeaIds = const []})
    : invitations = List.unmodifiable(invitations), greetings = List.unmodifiable(greetings),
      favoriteIdeaIds = List.unmodifiable(favoriteIdeaIds);

  final List<DateInvitation> invitations;
  final List<FlowerGreeting> greetings;
  final List<String> favoriteIdeaIds;
  GiftData copyWith({List<DateInvitation>? invitations, List<FlowerGreeting>? greetings,
    List<String>? favoriteIdeaIds}) => GiftData(
      invitations: invitations ?? this.invitations, greetings: greetings ?? this.greetings,
      favoriteIdeaIds: favoriteIdeaIds ?? this.favoriteIdeaIds);
  Map<String, Object?> toJson() => {
    'invitations': invitations.map((item) => item.toJson()).toList(),
    'greetings': greetings.map((item) => item.toJson()).toList(),
    'favoriteIdeaIds': favoriteIdeaIds,
  };
  factory GiftData.fromJson(Map<String, dynamic> json) {
    final invitations = _objects(json['invitations']).map(DateInvitation.fromJson).toList();
    final greetings = _objects(json['greetings']).map(FlowerGreeting.fromJson).toList();
    final favorites = json['favoriteIdeaIds'];
    if (favorites is! List || favorites.any((item) => item is! String || item.trim().isEmpty)) {
      throw const FormatException('Invalid favorite ideas.');
    }
    _unique(invitations.map((item) => item.id));
    _unique(greetings.map((item) => item.id));
    _unique(favorites.cast<String>());
    return GiftData(invitations: invitations, greetings: greetings,
      favoriteIdeaIds: favorites.cast<String>());
  }
}

String _text(Map<String, dynamic> json, String key, {bool blank = false}) {
  final value = json[key];
  if (value is! String || (!blank && value.trim().isEmpty)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}
String? _nullableText(Map<String, dynamic> json, String key) =>
  json[key] == null ? null : _text(json, key);
int _version(Object? value) {
  if (value is! int || value < 1) throw const FormatException('Invalid version.');
  return value;
}
DateTime _date(Map<String, dynamic> json, String key) {
  final text = _text(json, key);
  final value = DateTime.tryParse(text);
  if (value == null || value.isUtc || text.endsWith('Z') ||
      localDateTime(value).toIso8601String() != text) {
    throw FormatException('Invalid local $key.');
  }
  return value;
}
List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw const FormatException('Invalid gift collection.');
  }
  return value.cast<Map<String, dynamic>>();
}
void _unique(Iterable<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw const FormatException('Duplicate gift ID.');
  }
}

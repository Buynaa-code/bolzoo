import 'dart:typed_data';

class ContentItem {
  ContentItem.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String, kind = json['kind'] as String,
      ownerId = json['owner_id'] as String, ownerName = json['owner_name'] as String? ?? '',
      pairId = json['pair_id'] as String?, version = json['version'] as int,
      revision = json['revision'] as int, deleted = json['state'] == 'deleted',
      partner = json['role'] == 'partner',
      updatedAt = DateTime.parse(json['updated_at'] as String),
      payload = Map<String, dynamic>.from(json['payload'] as Map);
  final String id, kind, ownerId, ownerName;
  final String? pairId;
  final int version, revision;
  final bool deleted, partner;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
}

class ContentException implements Exception {
  const ContentException(this.code);
  final String code;
  @override
  String toString() => switch (code) {
    'version_conflict' => 'Мэдээлэл өөрчлөгдсөн байна. Шинэчлээд дахин оролдоно уу.',
    'not_paired' || 'pair_required' || 'pair_not_active' => 'Эхлээд Бид хэсэгт хосоороо холбогдоорой.',
    'forbidden' || 'not_found' => 'Энэ мэдээлэлд хандах эрхгүй эсвэл устсан байна.',
    'validation' => 'Оруулсан мэдээллээ шалгана уу.',
    'rate_limited' => 'Түр хүлээгээд дахин оролдоно уу.',
    _ => 'Сервертэй холбогдож чадсангүй. Дахин оролдоно уу.',
  };
}

abstract interface class ContentRepository {
  String get userId;
  Future<List<ContentItem>> snapshot();
  Future<ContentItem> save({required String commandId, required String id,
    required String kind, required Map<String, Object?> payload,
    required bool shared, int? expectedVersion});
  Future<ContentItem> delete({required String commandId, required String id, required int expectedVersion});
  Future<ContentItem> respond({required String commandId, required String id, required int expectedVersion, required String action, DateTime? proposedAt});
  Future<ContentItem> react({required String commandId, required String id, required bool liked});
  Future<ContentItem> comment({required String commandId, required String id, required String text});
  Future<String> uploadPhoto(String itemId, Uint8List bytes, String extension);
  Future<Uint8List> downloadPhoto(String key);
}

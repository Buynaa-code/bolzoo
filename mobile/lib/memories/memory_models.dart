import 'dart:typed_data';

class SharedMemory {
  const SharedMemory({
    required this.id,
    required this.pairId,
    required this.creatorId,
    required this.day,
    required this.title,
    required this.note,
    required this.sticker,
    required this.version,
    required this.createdAt,
  });
  final String id, pairId, creatorId, day, title, note, sticker;
  final int version;
  final DateTime createdAt;
  factory SharedMemory.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final v = json[key];
      if (v is! String) throw const FormatException();
      return v;
    }

    final day = text('day');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        json['version'] is! int ||
        (json['version'] as int) < 1 ||
        !['rounded', 'polaroid'].contains(json['sticker']))
      throw const FormatException();
    return SharedMemory(
      id: text('id'),
      pairId: text('pair_id'),
      creatorId: text('creator_id'),
      day: day,
      title: text('title'),
      note: text('note'),
      sticker: text('sticker'),
      version: json['version'] as int,
      createdAt: DateTime.parse(text('created_at')),
    );
  }
}

class MemoryPhoto {
  const MemoryPhoto({required this.photo, required this.thumbnail});
  final Uint8List photo, thumbnail;
}

class MemoryDraft {
  const MemoryDraft({
    required this.day,
    required this.title,
    required this.note,
    required this.sticker,
    required this.image,
  });
  final String day, title, note, sticker;
  final MemoryPhoto image;
}

class MemoryFailure implements Exception {
  const MemoryFailure(this.code);
  final String code;
  String get message => switch (code) {
    'unauthenticated' => 'Нэвтрэлт дууслаа. Дахин нэвтрээрэй.',
    'pair_changed' ||
    'pair_required' ||
    'forbidden' => 'Хосын холболт өөрчлөгдсөн байна.',
    'not_found' =>
      'Энэ дурсамжийг устгасан эсвэл харах боломжгүй болсон байна.',
    'quota_exceeded' =>
      'Өдөрт 10 зураг, нэг өдөрт 10 дурсамж хүртэл хадгална. Нийт 1,000 дурсамжийн хязгаартай.',
    'invalid_photo' => 'Зургийг уншиж чадсангүй. Өөр зураг сонгоорой.',
    'upload_in_progress' =>
      'Зураг хадгалагдаж байна. Түр хүлээгээд дахин оролдоорой.',
    'payload_too_large' ||
    'photo_too_large' => 'Зураг хэт том байна. Өөр зураг сонгоорой.',
    'unavailable' || 'temporarily_unavailable' =>
      'Зургийн үйлчилгээ түр боломжгүй байна. Дахин оролдоорой.',
    _ => 'Дурсамжийг хадгалж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
  };
}

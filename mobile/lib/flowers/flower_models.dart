import 'package:uuid/uuid.dart';

const flowerTemplates = ['letter', 'garden', 'bloom'];
const flowerColors = ['rose', 'sage', 'peach'];
const flowerOccasions = ['Зүгээр л', 'Төрсөн өдөр', 'Баярлалаа'];

class FlowerFailure implements Exception {
  const FlowerFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  String get message => switch (code) {
    'unauthenticated' => 'Нэвтрэлт дууслаа. Дахин нэвтрээрэй.',
    'pair_required' || 'pair_changed' => 'Хосын холболт өөрчлөгдсөн байна.',
    'quota_exceeded' =>
      'Өнөөдрийн цэцгийн хязгаарт хүрлээ. Дараа дахин илгээгээрэй.',
    'not_found' => 'Энэ мэндчилгээ харагдах боломжгүй болсон байна.',
    'invalid_response' =>
      'Мэдээллийг баталгаажуулж чадсангүй. Дахин шалгаарай.',
    'network_error' ||
    'temporarily_unavailable' => 'Холболт түр тасарлаа. Дахин оролдоорой.',
    _ => 'Мэндчилгээг илгээж чадсангүй. Мэдээллээ шалгаарай.',
  };
}

String _text(Object? value) {
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

class DigitalFlower {
  const DigitalFlower({
    required this.id,
    required this.pairId,
    required this.senderId,
    required this.recipientId,
    required this.senderName,
    required this.recipientName,
    required this.templateId,
    required this.colorId,
    required this.occasion,
    required this.message,
    required this.createdAt,
  });
  final String id, pairId, senderId, recipientId, senderName, recipientName;
  final String templateId, colorId, occasion, message;
  final DateTime createdAt;
  factory DigitalFlower.fromJson(Map<String, dynamic> json) {
    final template = _text(json['template_id']);
    final color = _text(json['color_id']);
    final occasion = _text(json['occasion']);
    final message = _text(json['message']);
    final created = DateTime.parse(_text(json['created_at']));
    if (!flowerTemplates.contains(template) ||
        !flowerColors.contains(color) ||
        !flowerOccasions.contains(occasion) ||
        message.length > 500 ||
        !created.isUtc) {
      throw const FormatException();
    }
    return DigitalFlower(
      id: _text(json['id']),
      pairId: _text(json['pair_id']),
      senderId: _text(json['sender_id']),
      recipientId: _text(json['recipient_id']),
      senderName: _text(json['sender_name']),
      recipientName: _text(json['recipient_name']),
      templateId: template,
      colorId: color,
      occasion: occasion,
      message: message,
      createdAt: created,
    );
  }
}

class FlowersSnapshot {
  const FlowersSnapshot({
    required this.paired,
    this.pairId,
    this.partnerId,
    this.partnerName,
    this.gifts = const [],
  });
  final bool paired;
  final String? pairId, partnerId, partnerName;
  final List<DigitalFlower> gifts;
  factory FlowersSnapshot.fromJson(Map<String, dynamic> json, String actor) {
    if (json['paired'] == false) return const FlowersSnapshot(paired: false);
    if (json['paired'] != true) throw const FormatException();
    final pair = _text(json['pair_id']);
    final partner = json['partner'] as Map<String, dynamic>;
    final partnerId = _text(partner['id']);
    final gifts = (json['gifts'] as List)
        .map((e) => DigitalFlower.fromJson(e as Map<String, dynamic>))
        .toList();
    if (partnerId == actor ||
        gifts.any(
          (g) =>
              g.pairId != pair ||
              !((g.senderId == actor && g.recipientId == partnerId) ||
                  (g.senderId == partnerId && g.recipientId == actor)),
        )) {
      throw const FormatException();
    }
    return FlowersSnapshot(
      paired: true,
      pairId: pair,
      partnerId: partnerId,
      partnerName: _text(partner['display_name']),
      gifts: List.unmodifiable(gifts),
    );
  }
}

class FlowerDraft {
  const FlowerDraft({
    this.templateId = 'letter',
    this.colorId = 'rose',
    this.occasion = 'Зүгээр л',
    required this.message,
  });
  final String templateId, colorId, occasion, message;
  Map<String, dynamic> toJson() {
    final text = message.trim();
    if (!flowerTemplates.contains(templateId) ||
        !flowerColors.contains(colorId) ||
        !flowerOccasions.contains(occasion) ||
        text.isEmpty ||
        text.length > 500 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(text)) {
      throw const FlowerFailure('validation');
    }
    return {
      'template_id': templateId,
      'color_id': colorId,
      'occasion': occasion,
      'message': text,
    };
  }
}

class FlowerCommand {
  FlowerCommand(String pair, FlowerDraft draft)
    : body = Map.unmodifiable({
        'command_id': const Uuid().v4(),
        'expected_pair_id': pair,
        ...draft.toJson(),
      });
  final Map<String, dynamic> body;
}

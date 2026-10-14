import 'dart:async';
import 'package:hamtdaa/flowers/flower_models.dart';
import 'package:hamtdaa/flowers/flower_repository.dart';

Map<String, dynamic> giftJson({
  String id = 'gift-1',
  String sender = 'b',
  String recipient = 'a',
  String pair = 'pair-a',
}) => {
  'id': id,
  'pair_id': pair,
  'sender_id': sender,
  'recipient_id': recipient,
  'sender_name': 'Тэмүүлэн',
  'recipient_name': 'Ану',
  'template_id': 'letter',
  'color_id': 'rose',
  'occasion': 'Зүгээр л',
  'message': 'Чамтай өдөр бүр илүү гоё.',
  'created_at': '2026-10-14T04:00:00.000Z',
};
Map<String, dynamic> flowersJson({
  bool paired = true,
  String pair = 'pair-a',
  List<Map<String, dynamic>> gifts = const [],
  String? cursor,
}) => {
  'ok': true,
  'paired': paired,
  'pair_id': paired ? pair : null,
  'partner': paired ? {'id': 'b', 'display_name': 'Тэмүүлэн'} : null,
  'gifts': gifts,
  'next_cursor': cursor,
};

class FakeFlowersRepository implements FlowersRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  bool current = true;
  Map<String, dynamic> value = flowersJson();
  Future<FlowersSnapshot> Function()? onState;
  Future<String> Function(FlowerCommand)? onSend;
  final commands = <FlowerCommand>[];
  @override
  String get actorId => 'a';
  @override
  bool get isCurrent => current;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<FlowersSnapshot> state() async => onState == null
      ? FlowersSnapshot.fromJson(value, actorId)
      : await onState!();
  @override
  Future<String> send(FlowerCommand command) async {
    commands.add(command);
    if (onSend != null) return onSend!(command);
    value = {
      ...value,
      'gifts': [giftJson(sender: 'a', recipient: 'b')],
    };
    return 'gift-1';
  }

  void invalidate() {
    current = false;
    changes.add(null);
  }

  @override
  Future<void> dispose() async {
    current = false;
    await changes.close();
  }
}

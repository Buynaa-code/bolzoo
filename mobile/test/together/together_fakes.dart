import 'dart:async';
import 'package:hamtdaa/cloudflare/cloudflare_session_storage.dart';
import 'package:hamtdaa/cloudflare/cloudflare_transport.dart';
import 'package:hamtdaa/together/together_models.dart';
import 'package:hamtdaa/together/together_repository.dart';

final today = DateTime.utc(2026, 10, 6, 4);
const pairId = '98bd1384-1edf-4890-8d6c-d42287e71142';
const otherPairId = '1cbe789d-215f-47a3-bf83-42130c373551';
Map<String, dynamic> dailyJson({String? mine, String? partner, bool both = false, String day = '2026-10-06'}) => {
  'day': day, 'question_id': 'dq-v1:$day:7', 'question': 'Хамтдаа өнгөрүүлсэн хамгийн гоё мөч юу вэ?',
  'my_answer': mine, 'partner_answer': partner, 'both_answered': both,
};
Map<String, dynamic> eventJson({String creator = 'a', String title = 'Кофе уух уу?', int version = 1, String status = 'pending'}) => {
  'id': 'event-1', 'title': title, 'note': 'Сайхан яриа', 'location': 'Little Heaven',
  'starts_at': '2026-10-06T10:00:00.000Z', 'ends_at': null,
  'creator_id': creator, 'status': status, 'version': version,
};
Map<String, dynamic> stateJson({bool paired = true, String pair = pairId, List<Map<String, dynamic>> events = const [], Map<String, dynamic>? daily}) => {
  'ok': true, 'paired': paired, 'pair_id': paired ? pair : null,
  'partner': paired ? {'id': 'b', 'display_name': 'Тэмүүлэн'} : null,
  'events': paired ? events : <Object>[], 'daily': paired ? daily ?? dailyJson() : null,
};

class TogetherFakeRepository implements TogetherRepository {
  final changes = StreamController<void>.broadcast(sync: true);
  Map<String, dynamic> value = stateJson();
  TogetherHistory historyValue = const TogetherHistory([], null);
  Future<TogetherSnapshot> Function(String)? onState;
  Future<void> Function(TogetherCommand)? onMutation;
  Future<TogetherHistory> Function(String?)? onHistory;
  final commands = <TogetherCommand>[];
  final months = <String>[];
  final cursors = <String?>[];
  bool current = true;
  @override
  String get actorId => 'a';
  @override
  bool get isCurrent => current;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<TogetherSnapshot> state(String month) async {
    months.add(month);
    return onState == null ? TogetherSnapshot.fromJson(value) : await onState!(month);
  }
  @override
  Future<void> mutate(TogetherCommand command) async {
    commands.add(command);
    if (onMutation != null) return onMutation!(command);
    final body = command.body;
    final existing = (value['events'] as List).cast<Map<String, dynamic>>();
    switch (command.path) {
      case 'calendar/create':
        value = {...value, 'events': [...existing, {
          ...eventJson(), 'title': body['title'], 'note': body['note'], 'location': body['location'],
          'starts_at': body['starts_at'], 'ends_at': body['ends_at'],
        }]};
      case 'calendar/update':
        value = {...value, 'events': [for (final event in existing)
          if (event['id'] == body['id']) {...event, 'title': body['title'], 'note': body['note'], 'location': body['location'],
            'starts_at': body['starts_at'], 'ends_at': body['ends_at'], 'status': 'pending', 'version': (event['version'] as int) + 1}
          else event]};
      case 'calendar/delete':
        value = {...value, 'events': existing.where((e) => e['id'] != body['id']).toList()};
      case 'calendar/respond':
        value = {...value, 'events': [for (final event in existing)
          if (event['id'] == body['id']) {...event, 'status': body['response'], 'version': (event['version'] as int) + 1} else event]};
      case 'daily/answer':
        value = {...value, 'daily': {...value['daily'] as Map<String, dynamic>, 'my_answer': body['answer']}};
    }
  }
  @override
  Future<TogetherHistory> history({String? beforeDay}) async {
    cursors.add(beforeDay);
    return onHistory == null ? historyValue : await onHistory!(beforeDay);
  }
  void invalidate() { current = false; changes.add(null); }
  @override
  Future<void> dispose() async { current = false; await changes.close(); }
}

class TogetherStorage implements CloudflareSessionStorage {
  String? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class TogetherTransport implements CloudflareTransport {
  final calls = <({String method, String path, String? token, Map<String, dynamic>? body})>[];
  Future<CloudflareResponse> Function(String, Map<String, dynamic>?)? onCall;
  @override
  Future<CloudflareResponse> send(String method, String path, {String? token, Map<String, dynamic>? body}) async {
    if (path == '/v1/auth/verify-code') {
      final actor = (body!['email'] as String).split('@').first;
      return CloudflareResponse(200, {'ok': true, 'token': 'token-$actor',
        'user': {'id': actor, 'email': body['email']},
        'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()});
    }
    if (path == '/v1/auth/sign-out') return const CloudflareResponse(200, {'ok': true});
    calls.add((method: method, path: path, token: token, body: body));
    return onCall == null ? CloudflareResponse(200, stateJson()) : await onCall!(path, body);
  }
  @override
  void close() {}
}

import 'dart:async';

import 'package:hamtdaa/wishes/wish_models.dart';
import 'package:hamtdaa/wishes/wish_repository.dart';

const wishPair = '98bd1384-1edf-4890-8d6c-d42287e71142';
const wishOtherPair = '1cbe789d-215f-47a3-bf83-42130c373551';
const wishId = 'bcf3c123-472e-4bed-b3c7-729ba35b89f1';
const wishCommand = 'b3291ca8-498d-48de-a8ce-2e2e8256d803';

Map<String, dynamic> wishJson({
  String id = wishId,
  String pair = wishPair,
  String actor = 'a',
  String status = 'idea',
  bool myLiked = true,
  bool partnerLiked = false,
  int version = 1,
  String? eventStatus,
}) => {
  'id': id,
  'pair_id': pair,
  'creator_id': actor,
  'title': 'Хамтдаа кофе',
  'note': 'Амралтын өдөр',
  'location': 'Улаанбаатар',
  'category': 'food',
  'budget': 'low',
  'status': status,
  'version': version,
  'my_liked': myLiked,
  'partner_liked': partnerLiked,
  'event_id': status == 'idea' ? null : 'event-1',
  'event_status': status == 'idea' ? null : eventStatus ?? 'accepted',
  'event_starts_at': status == 'idea' ? null : '2020-01-01T10:00:00.000Z',
  'created_at': '2020-01-01T00:00:00.000Z',
  'updated_at': '2020-01-01T01:00:00.000Z',
};

SharedWish wish({
  String pair = wishPair,
  String actor = 'a',
  String status = 'idea',
  bool myLiked = true,
  bool partnerLiked = false,
  int version = 1,
  String? eventStatus,
}) => SharedWish.fromJson(
  wishJson(
    pair: pair,
    actor: actor,
    status: status,
    myLiked: myLiked,
    partnerLiked: partnerLiked,
    version: version,
    eventStatus: eventStatus,
  ),
);

const wishDraft = WishDraft(
  title: 'Хамтдаа кофе',
  note: 'Амралтын өдөр',
  location: 'Улаанбаатар',
  category: 'food',
  budget: 'low',
);

Future<void> flushWishes() => Future<void>.delayed(Duration.zero);

class WishFakeRepository implements WishRepository {
  WishFakeRepository({this.actorId = 'a'});
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  final String actorId;
  bool active = true;
  bool disposed = false;
  List<SharedWish> rows = [];
  final calls =
      <
        ({
          String operation,
          String command,
          SharedWish? wish,
          WishDraft? draft,
          bool? liked,
          DateTime? starts,
          DateTime? ends,
        })
      >[];
  Future<List<SharedWish>> Function(String)? onList;
  Future<SharedWish> Function(String, String, WishDraft)? onCreate;
  Future<SharedWish> Function(String, SharedWish, String)? onMutation;
  Future<void> Function(SharedWish, String)? onDelete;

  @override
  bool get isCurrent => active && !disposed;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<List<SharedWish>> list(String pairId) async => onList != null
      ? onList!(pairId)
      : rows.where((row) => row.pairId == pairId).toList();
  @override
  Future<SharedWish> create(
    String pairId,
    String commandId,
    WishDraft draft,
  ) async {
    calls.add((
      operation: 'create',
      command: commandId,
      wish: null,
      draft: draft,
      liked: null,
      starts: null,
      ends: null,
    ));
    final result = onCreate == null
        ? wish(pair: pairId, actor: actorId)
        : await onCreate!(pairId, commandId, draft);
    rows = [result, ...rows.where((row) => row.id != result.id)];
    return result;
  }

  @override
  Future<SharedWish> like(SharedWish wish, String commandId, bool liked) async {
    calls.add((
      operation: 'like',
      command: commandId,
      wish: wish,
      draft: null,
      liked: liked,
      starts: null,
      ends: null,
    ));
    return _mutate('like', wish, commandId, {'my_liked': liked});
  }

  @override
  Future<SharedWish> plan(
    SharedWish wish,
    String commandId,
    DateTime startsAt, {
    DateTime? endsAt,
  }) async {
    calls.add((
      operation: 'plan',
      command: commandId,
      wish: wish,
      draft: null,
      liked: null,
      starts: startsAt,
      ends: endsAt,
    ));
    return _mutate('plan', wish, commandId, {
      'status': 'planned',
      'event_id': 'event-1',
      'event_status': 'pending',
      'event_starts_at': startsAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<SharedWish> complete(SharedWish wish, String commandId) async {
    calls.add((
      operation: 'complete',
      command: commandId,
      wish: wish,
      draft: null,
      liked: null,
      starts: null,
      ends: null,
    ));
    return _mutate('complete', wish, commandId, {'status': 'done'});
  }

  Future<SharedWish> _mutate(
    String operation,
    SharedWish value,
    String command,
    Map<String, dynamic> changes,
  ) async {
    final result = onMutation != null
        ? await onMutation!(operation, value, command)
        : SharedWish.fromJson({
            ...wishJson(
              pair: value.pairId,
              actor: value.creatorId,
              status: value.status,
              myLiked: value.myLiked,
              partnerLiked: value.partnerLiked,
              version: value.version + 1,
              eventStatus: value.eventStatus,
            ),
            ...changes,
          });
    rows = [result, ...rows.where((row) => row.id != result.id)];
    return result;
  }

  @override
  Future<void> delete(SharedWish wish, String commandId) async {
    calls.add((
      operation: 'delete',
      command: commandId,
      wish: wish,
      draft: null,
      liked: null,
      starts: null,
      ends: null,
    ));
    if (onDelete != null) await onDelete!(wish, commandId);
    rows = rows.where((row) => row.id != wish.id).toList();
  }

  @override
  Future<WishExport> exportData(String pairId) async =>
      WishExport(wishes: [], likedWishIds: []);
  void invalidate() {
    active = false;
    changes.add(null);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await changes.close();
  }
}

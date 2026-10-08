import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/wishes/wish_models.dart';

import 'wish_fakes.dart';

void main() {
  test('valid idea, planned and completed records retain typed values', () {
    final idea = SharedWish.fromJson(wishJson(partnerLiked: true));
    expect(idea.canPlan, isTrue);
    expect(idea.createdAt.isUtc, isTrue);
    expect(idea.eventId, isNull);
    final planned = wish(status: 'planned');
    expect(planned.canCompleteAt(DateTime.utc(2020, 1, 1, 9)), isFalse);
    expect(planned.canCompleteAt(DateTime.utc(2020, 1, 1, 10)), isTrue);
    expect(
      wish(status: 'planned', eventStatus: 'pending').canComplete,
      isFalse,
    );
    expect(
      wish(status: 'planned', eventStatus: 'declined').canComplete,
      isFalse,
    );
    final done = SharedWish.fromJson({
      ...wishJson(status: 'done'),
      'event_id': null,
      'event_status': null,
      'event_starts_at': null,
    });
    expect(done.isDone, isTrue);
  });

  test('rejects malformed DTOs instead of normalizing unsupported state', () {
    final invalid = <Map<String, dynamic>>[
      {'title': ''},
      {'title': 'bad\u0000title'},
      {'title': 'x' * 81},
      {'note': 'x' * 501},
      {'location': 'x' * 121},
      {'category': 'unknown'},
      {'budget': 'costly'},
      {'status': 'pending'},
      {'version': 0},
      {'version': 1.2},
      {'my_liked': 1},
      {'partner_liked': null},
      {'id': '../other'},
      {'created_at': '2026-02-31T10:00:00.000Z'},
      {'created_at': '2026-02-01'},
      {'updated_at': '2019-01-01T00:00:00.000Z'},
      {'event_id': 'event-1'},
      {'event_status': 'accepted'},
      {'status': 'planned'},
    ];
    for (final change in invalid) {
      expect(
        () => SharedWish.fromJson({...wishJson(), ...change}),
        throwsFormatException,
        reason: '$change',
      );
    }
  });

  test(
    'draft trims text and rejects excessive input before network access',
    () {
      expect(
        const WishDraft(title: '  Кофе  ', note: ' ').toJson()['title'],
        'Кофе',
      );
      for (final draft in [
        const WishDraft(title: ' '),
        WishDraft(title: 'x' * 81),
        const WishDraft(title: 'x', category: 'unknown'),
      ]) {
        expect(draft.toJson, throwsA(isA<WishFailure>()));
      }
    },
  );

  test(
    'account export rejects partner records and copies only allowed fields',
    () {
      final own = {...wishJson(), 'extra_private_value': 'discard'}
        ..remove('partner_liked');
      Map<String, dynamic> envelope(
        List<dynamic> rows, {
        List<dynamic>? likes,
      }) => {
        'ok': true,
        'pair_id': wishPair,
        'wishes': rows,
        'likes':
            likes ??
            [
              {'wish_id': wishId, 'liked': true},
            ],
      };
      final exported = WishExport.fromJson(
        envelope([own]),
        pairId: wishPair,
        actorId: 'a',
      );
      expect(
        exported.wishes.single.containsKey('extra_private_value'),
        isFalse,
      );
      expect(exported.wishes.single.containsKey('partner_liked'), isFalse);
      expect(exported.likedWishIds, [wishId]);
      expect(
        () => exported.wishes.single['title'] = 'changed',
        throwsUnsupportedError,
      );
      for (final value in [
        envelope([wishJson()]),
        envelope([
          {...own, 'creator_id': 'b'},
        ]),
        envelope([
          {...own, 'pair_id': wishOtherPair},
        ]),
        envelope([own, own]),
        envelope(
          [own],
          likes: [
            {'wish_id': wishId, 'liked': false},
          ],
        ),
      ]) {
        expect(
          () => WishExport.fromJson(value, pairId: wishPair, actorId: 'a'),
          throwsFormatException,
        );
      }
    },
  );
}

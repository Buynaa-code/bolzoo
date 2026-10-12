import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/data/gift_catalog.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/features/ideas/ideas_screen.dart';
import 'package:hamtdaa/features/notifications/notifications_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

DateInvitation invitation({InvitationState state = InvitationState.draft}) =>
    DateInvitation(
      id: 'edac38fa-ed5b-4b53-a26f-29db8f0e4ae2',
      templateId: 'coffee',
      title: 'Кофе уух уу?',
      recipientName: 'Ану',
      senderName: 'Тэмүүлэн',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      createdAt: DateTime.now(),
      place: 'Кафе',
      message: 'Хамт ярилцъя.',
      state: state,
      creatorId: 'creator',
      recipientId: state == InvitationState.draft ? null : 'recipient',
    );

class FakeGateway implements GiftGateway {
  FakeGateway({this.currentUserId = 'creator'});
  @override
  final String currentUserId;
  int publishes = 0, responses = 0;
  bool fail = false;
  Completer<DateInvitation>? pending;
  Completer<DateInvitation>? pendingResponse;
  Completer<List<DateInvitation>>? pendingList;
  final List<String> commandIds = [];
  final List<InvitationResponse> answers = [];
  @override
  Future<List<DateInvitation>> list() async => pendingList?.future ?? [];
  @override
  Future<DateInvitation> publish(
    DateInvitation draft, {
    required String commandId,
  }) async {
    publishes++;
    commandIds.add(commandId);
    if (pending != null) return pending!.future;
    if (fail)
      throw const GiftGatewayException('Холболтоо шалгаад дахин оролдоорой.');
    return draft.copyWith(
      state: InvitationState.pending,
      recipientId: 'recipient',
      version: 2,
    );
  }

  @override
  Future<DateInvitation> respond(
    DateInvitation invitation, {
    required InvitationResponse response,
    required String commandId,
    DateTime? proposedAt,
  }) async {
    responses++;
    commandIds.add(commandId);
    answers.add(response);
    if (pendingResponse != null) return pendingResponse!.future;
    if (fail)
      throw const GiftGatewayException('Холболтоо шалгаад дахин оролдоорой.');
    return invitation.copyWith(
      state: response == InvitationResponse.accept
          ? InvitationState.accepted
          : InvitationState.proposed,
      proposedAt: proposedAt,
      version: invitation.version + 1,
    );
  }
}

class PrivacyRepository implements ContentRepository {
  PrivacyRepository(this.items, {this.userId = 'recipient'});
  final List<ContentItem> items;
  @override
  final String userId;
  @override
  Future<List<ContentItem>> snapshot() async => items;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ContentItem remoteInvitation(DateInvitation invited, {bool partner = true}) =>
    ContentItem.fromJson({
      'id': invited.id,
      'kind': 'invitation',
      'owner_id': 'creator',
      'owner_name': 'Тэмүүлэн',
      'pair_id': 'pair-1',
      'version': invited.version,
      'revision': 1,
      'state': 'active',
      'role': partner ? 'partner' : 'owner',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {...invited.toJson(), 'status': 'pending'},
    });

Future<AppController> controller([MemoryAppStore? store]) async {
  final c = AppController(
    store ??
        MemoryAppStore(AppData(profile: const UserProfile(name: 'Тэмүүлэн'))),
  );
  await c.load();
  addTearDown(c.dispose);
  return c;
}

Future<void> pump(
  WidgetTester tester,
  Widget screen, {
  double scale = 1,
  double width = 390,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String value) async {
  final text = find.text(value);
  if (text.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      text,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final f = text.last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String value) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, value);
  await tester.pump();
}

void main() {
  test(
    'gift persistence round trips without mutating state or treating draft as delivered',
    () async {
      final store = MemoryAppStore();
      final c = await controller(store);
      final draft = invitation();
      await c.saveInvitation(draft);
      await c.toggleFavoriteIdea('coffee');
      final data = AppData.fromJson(
        (await store.read()).toJson().cast<String, dynamic>(),
      );
      expect(data.gifts.invitations.single.state, InvitationState.draft);
      expect(data.gifts.favoriteIdeaIds, ['coffee']);
      expect(data.gifts.invitations.single.startsAt, draft.startsAt);
      expect(
        () => GiftData.fromJson({
          'invitations': [],
          'greetings': [],
          'favoriteIdeaIds': ['coffee', 'coffee'],
        }),
        throwsFormatException,
      );
      final invalid = draft.toJson()..['startsAt'] = '2026-02-30T16:00:00.000';
      expect(
        () => DateInvitation.fromJson(invalid.cast<String, dynamic>()),
        throwsFormatException,
      );
    },
  );

  testWidgets('ideas search category and favorites use real saved state', (
    tester,
  ) async {
    final c = await controller();
    await pump(tester, IdeasScreen(controller: c));
    await tester.tap(find.byKey(const Key('favorite-coffee')));
    await tester.pumpAndSettle();
    expect(c.data.gifts.favoriteIdeaIds, ['coffee']);
    await tester.enterText(find.byKey(const Key('ideaSearch')), 'алх');
    await tester.pumpAndSettle();
    expect(find.text('Хамтдаа алхъя'), findsOneWidget);
    expect(find.text('Кофе, бас яриа'), findsNothing);
    await tapText(tester, 'Дотор');
    expect(find.text('Тохирох санаа олдсонгүй.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'idea invitation editor validates and saves reusable draft without sending',
    (tester) async {
      final c = await controller();
      final gateway = FakeGateway();
      await pump(
        tester,
        InvitationEditor(
          controller: c,
          gateway: gateway,
          idea: dateIdeas.first,
        ),
      );
      await tapText(tester, 'Урилгаа харах');
      expect(c.data.gifts.invitations, isEmpty);
      expect(gateway.publishes, 0);
      await enter(tester, 'inviteRecipient', 'Ану');
      await enter(tester, 'invitePlace', 'Little Heaven');
      await tapText(tester, 'Урилгаа харах');
      expect(find.byType(InvitationPreview), findsOneWidget);
      expect(c.data.gifts.invitations.single.recipientName, 'Ану');
      expect(c.data.gifts.invitations.single.state, InvitationState.draft);
      expect(gateway.publishes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creator preview cannot consent and retries publish with same command',
    (tester) async {
      final c = await controller();
      final gateway = FakeGateway()..fail = true;
      await pump(
        tester,
        InvitationPreview(
          controller: c,
          invitation: invitation(),
          gateway: gateway,
        ),
      );
      expect(find.text('Тэгье ♡'), findsNothing);
      await tapText(tester, 'Хосдоо илгээх');
      expect(find.text('Холболтоо шалгаад дахин оролдоорой.'), findsOneWidget);
      gateway.fail = false;
      await tapText(tester, 'Хосдоо илгээх');
      expect(gateway.commandIds[0], gateway.commandIds[1]);
      expect(find.text('Хүлээж байна'), findsOneWidget);
      expect(find.text('Хосдоо илгээх'), findsNothing);
    },
  );

  testWidgets('rapid publish taps create only one in-flight request', (
    tester,
  ) async {
    final c = await controller();
    final gateway = FakeGateway()..pending = Completer();
    await pump(
      tester,
      InvitationPreview(
        controller: c,
        invitation: invitation(),
        gateway: gateway,
      ),
    );
    final send = find.text('Хосдоо илгээх');
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.tap(send);
    await tester.pump();
    expect(gateway.publishes, 1);
    gateway.pending!.complete(invitation(state: InvitationState.pending));
    await tester.pumpAndSettle();
    expect(find.text('Хүлээж байна'), findsOneWidget);
  });

  testWidgets(
    'only the verified recipient can accept and success comes from server',
    (tester) async {
      final c = await controller();
      final creator = FakeGateway();
      await pump(
        tester,
        InvitationRecipientScreen(
          controller: c,
          gateway: creator,
          invitation: invitation(state: InvitationState.pending),
        ),
      );
      expect(find.text('Тэгье ♡'), findsNothing);
      expect(creator.responses, 0);
      final recipient = FakeGateway(currentUserId: 'recipient')..fail = true;
      await pump(
        tester,
        InvitationRecipientScreen(
          key: const Key('recipient'),
          controller: c,
          gateway: recipient,
          invitation: invitation(state: InvitationState.pending),
        ),
      );
      await tapText(tester, 'Тэгье ♡');
      expect(find.text('Зөвшөөрсөн'), findsNothing);
      recipient.fail = false;
      await tapText(tester, 'Тэгье ♡');
      expect(recipient.commandIds.first, recipient.commandIds.last);
      expect(find.text('Зөвшөөрсөн'), findsOneWidget);
      expect(c.data.gifts.invitations, isEmpty);
    },
  );

  testWidgets('flower editor saves chosen template color and message', (
    tester,
  ) async {
    final c = await controller();
    await pump(tester, FlowerEditor(controller: c, occasion: 'Баярлалаа'));
    await tester.tap(find.byKey(const Key('flower-template-bloom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flower-color-sage')));
    await tester.pumpAndSettle();
    await enter(tester, 'flowerRecipient', 'Ану');
    await enter(tester, 'flowerMessage', 'Хажууд байдагт баярлалаа.');
    await tapText(tester, 'Мэндчилгээгээ харах');
    expect(find.byType(FlowerPreview), findsOneWidget);
    final saved = c.data.gifts.greetings.single;
    expect(saved.templateId, 'bloom');
    expect(saved.colorId, 'sage');
    expect(saved.occasion, 'Баярлалаа');
    expect(saved.message, 'Хажууд байдагт баярлалаа.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'flower save memory is idempotent and actual export invokes share adapter',
    (tester) async {
      final c = await controller();
      final greeting = FlowerGreeting(
        id: newGiftId(),
        templateId: 'letter',
        colorId: 'rose',
        occasion: 'Зүгээр л',
        recipientName: 'Ану',
        senderName: 'Тэмүүлэн',
        message: 'Чамтай өдөр бүр илүү гоё.',
        createdAt: DateTime.now(),
      );
      await c.saveGreeting(greeting);
      var captures = 0, shares = 0;
      await pump(
        tester,
        FlowerPreview(
          controller: c,
          greeting: greeting,
          captureImage: (_) async {
            captures++;
            return '/tmp/gift-test.png';
          },
          shareImage: (_, _) async {
            shares++;
          },
        ),
      );
      await tapText(tester, 'Дурсамждаа хадгалах');
      expect(c.data.memories.single.id, 'flower_${greeting.id}');
      expect(captures, 1);
      expect(find.text('Дурсамжид хадгалсан'), findsOneWidget);
      await tapText(tester, 'Зураг татах / хуваалцах');
      expect(shares, 1);
      expect(c.data.memories.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text editor remains scrollable without overflow', (
    tester,
  ) async {
    final c = await controller();
    await pump(tester, FlowerEditor(controller: c), scale: 1.6);
    await enter(tester, 'flowerRecipient', 'Ану');
    await tapText(tester, 'Мэндчилгээгээ харах');
    expect(find.byType(FlowerPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'recipient can propose a time only after date and time confirmation',
    (tester) async {
      final c = await controller();
      final gateway = FakeGateway(currentUserId: 'recipient');
      await pump(
        tester,
        InvitationRecipientScreen(
          controller: c,
          gateway: gateway,
          invitation: invitation(state: InvitationState.pending),
        ),
      );
      await tapText(tester, 'Өөр цаг санал болгох');
      expect(gateway.responses, 0);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(gateway.responses, 0);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(gateway.answers.single, InvitationResponse.propose);
      expect(find.text('Өөр цаг санал болгосон'), findsOneWidget);
    },
  );

  testWidgets(
    'recipient content is hidden immediately when foreground access is revoked',
    (tester) async {
      final c = AppController(MemoryAppStore());
      await c.load();
      final invited = invitation(state: InvitationState.pending);
      final item = ContentItem.fromJson({
        'id': invited.id,
        'kind': 'invitation',
        'owner_id': 'creator',
        'owner_name': 'Тэмүүлэн',
        'pair_id': 'pair-1',
        'version': 1,
        'revision': 1,
        'state': 'active',
        'role': 'partner',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'payload': {...invited.toJson(), 'status': 'pending'},
      });
      c.connectCloud(PrivacyRepository([item]));
      await tester.pump();
      final gateway = FakeGateway(currentUserId: 'recipient');
      await pump(
        tester,
        InvitationRecipientScreen(
          controller: c,
          gateway: gateway,
          invitation: invited,
        ),
      );
      expect(find.byType(InvitationCard), findsOneWidget);
      c.setCloudForeground(false);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationCard), findsNothing);
      expect(find.text('Энэ урилгыг харах эрх дууссан байна.'), findsOneWidget);
      expect(gateway.responses, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('sent preview hides content when its remote access expires', (
    tester,
  ) async {
    final c = AppController(MemoryAppStore());
    await c.load();
    final invited = invitation(state: InvitationState.pending);
    c.connectCloud(
      PrivacyRepository([
        remoteInvitation(invited, partner: false),
      ], userId: 'creator'),
    );
    await tester.pump();
    await pump(
      tester,
      InvitationPreview(
        controller: c,
        invitation: invited,
        gateway: FakeGateway(),
      ),
    );
    expect(find.byType(InvitationCard), findsOneWidget);
    c.setCloudForeground(false);
    await tester.pumpAndSettle();
    expect(find.byType(InvitationCard), findsNothing);
    expect(find.text('Энэ урилгыг харах эрх дууссан байна.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('late recipient response cannot restore revoked content', (
    tester,
  ) async {
    final store = MemoryAppStore();
    final c = AppController(store);
    await c.load();
    final invited = invitation(state: InvitationState.pending);
    final repository = PrivacyRepository([remoteInvitation(invited)]);
    c.connectCloud(repository);
    await tester.pump();
    final gateway = FakeGateway(currentUserId: 'recipient')
      ..pendingResponse = Completer();
    await pump(
      tester,
      InvitationRecipientScreen(
        controller: c,
        gateway: gateway,
        invitation: invited,
      ),
    );
    final accept = find.text('Тэгье ♡');
    await tester.scrollUntilVisible(
      accept,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pump();
    expect(gateway.responses, 1);
    repository.items.clear();
    await c.refreshCloud();
    await tester.pump();
    gateway.pendingResponse!.complete(
      invited.copyWith(state: InvitationState.accepted),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InvitationCard), findsNothing);
    expect(find.text('Энэ урилгыг харах эрх дууссан байна.'), findsOneWidget);
    expect((await store.read()).gifts.invitations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'late inbox lookup cannot open an invitation after backgrounding',
    (tester) async {
      final c = AppController(MemoryAppStore());
      await c.load();
      final invited = invitation(state: InvitationState.pending);
      c.connectCloud(PrivacyRepository([remoteInvitation(invited)]));
      await tester.pump();
      final gateway = FakeGateway(currentUserId: 'recipient')
        ..pendingList = Completer();
      await pump(
        tester,
        NotificationsScreen(controller: c, giftGateway: gateway),
      );
      await tester.tap(
        find.byKey(Key('notice-${invited.id}:${invited.version}')),
      );
      await tester.pump();
      c.setCloudForeground(false);
      await tester.pump();
      gateway.pendingList!.complete([invited]);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationRecipientScreen), findsNothing);
      expect(find.byType(InvitationPreview), findsNothing);
      expect(find.text('Одоогоор мэдэгдэл алга'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'gift and idea flows remain readable on a small screen with large text',
    (tester) async {
      final c = await controller();
      final greeting = FlowerGreeting(
        id: 'layout-greeting',
        templateId: 'letter',
        colorId: 'rose',
        occasion: 'Зүгээр л',
        recipientName: 'Ану',
        senderName: 'Тэмүүлэн',
        message: 'Чамтай өдөр бүр илүү гоё.',
        createdAt: DateTime.now(),
      );
      final screens = <Widget>[
        IdeasScreen(controller: c),
        IdeaDetailScreen(idea: dateIdeas.last, controller: c),
        InvitationEditor(controller: c),
        InvitationPreview(controller: c, invitation: invitation()),
        InvitationRecipientScreen(
          controller: c,
          gateway: FakeGateway(currentUserId: 'recipient'),
          invitation: invitation(state: InvitationState.pending),
        ),
        Scaffold(body: FlowersHome(controller: c)),
        FlowerEditor(controller: c),
        FlowerPreview(controller: c, greeting: greeting),
      ];
      for (final screen in screens) {
        await pump(tester, screen, width: 320, scale: 1.6);
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
        for (var i = 0; i < 7; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType}',
          );
        }
      }
    },
  );
}

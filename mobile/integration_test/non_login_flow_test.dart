import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hamtdaa/main_supabase_legacy.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/gifts/gifts_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

class RecipientGateway implements GiftGateway {
  @override String get currentUserId=>'recipient-fixture';
  @override Future<List<DateInvitation>> list() async => [];
  @override Future<DateInvitation> publish(DateInvitation d,{required String commandId}) async=>d.copyWith(state:InvitationState.pending);
  @override Future<DateInvitation> respond(DateInvitation d,{required InvitationResponse response,required String commandId,DateTime? proposedAt}) async=>d.copyWith(state:response==InvitationResponse.accept?InvitationState.accepted:InvitationState.proposed,proposedAt:proposedAt);
}
void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> shot(WidgetTester t,String name) async { await t.pumpAndSettle(); await binding.takeScreenshot(name); }
  Future<void> tap(WidgetTester t,Finder finder) async { await t.ensureVisible(finder); await t.pumpAndSettle(); await t.tap(finder); await t.pumpAndSettle(); }
  Future<void> key(WidgetTester t,String id) => tap(t,find.byKey(ValueKey(id)));
  Future<void> enter(WidgetTester t,String id,String value) async {
    final finder=find.byKey(ValueKey(id));
    if(finder.evaluate().isEmpty) await t.scrollUntilVisible(finder,220,scrollable:find.byType(Scrollable).last);
    await t.ensureVisible(finder); await t.enterText(finder,value); await t.pumpAndSettle();
  }
  Future<void> tab(WidgetTester t,String label) => tap(t,find.descendant(of:find.byType(NavigationBar),matching:find.text(label)));
  Future<void> back(WidgetTester t) => tap(t,find.byTooltip('Буцах').first);
  testWidgets('native non-login user journey saves events memories places invitations and a rendered flower PNG', (t) async {
    final temp=await getTemporaryDirectory();
    final dir=Directory('${temp.path}/hamtdaa-ui-flow-${DateTime.now().microsecondsSinceEpoch}');
    await dir.create(recursive:true);
    final photo=File('${dir.path}/fixture.jpg');
    await photo.writeAsBytes((await rootBundle.load('assets/gifts/mountains.jpg')).buffer.asUint8List());
    final store=FileAppStore(File('${dir.path}/data.json'));
    final controller=AppController(store); await controller.load();
    await controller.updateProfile(UserProfile(name:'Ану',togetherSince:DateTime.now().subtract(const Duration(days:424))));
    await controller.saveMemory(MemoryEntry(id:'fixture-memory',title:'Тэрэлжийн нэг өдөр',date:DateTime.now().subtract(const Duration(days:5)),text:'Хамт байсан болохоор гоё.',place:'Тэрэлж',photoPath:photo.path));
    await t.pumpWidget(HamtdaaApp(controller:controller)); await t.pumpAndSettle();
    await shot(t,'01-home');
    await key(t,'homeNotificationsButton'); await shot(t,'05-notifications'); await back(t);
    await tab(t,'Хуанли'); await shot(t,'02-calendar');
    await key(t,'calendarAddEvent'); await enter(t,'eventTitle','Кофе уух уу?'); await enter(t,'eventPlace','Little Heaven'); await enter(t,'eventNote','Сайхан кофе, сайхан яриа ♡');
    FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle(); await shot(t,'04-event-editor');
    await key(t,'saveEventButton'); expect(controller.data.events,hasLength(1));
    await tap(t,find.text('Кофе уух уу?').hitTestable()); await shot(t,'03-event-detail');
    await tap(t,find.text('Дурсамж нэмэх')); await enter(t,'memoryTitle','Кофетой өглөө'); await enter(t,'memoryText','Сайхан ярилцлаа.');
    FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle(); await shot(t,'08-memory-editor'); await key(t,'saveMemoryButton');
    expect(controller.data.memories,hasLength(2)); await back(t);
    await tab(t,'Дурсамж'); await shot(t,'06-memories');
    await key(t,'memoryCard-fixture-memory'); await shot(t,'07-memory-detail');
    await key(t,'memoryLikeButton'); expect(controller.data.memories.firstWhere((m)=>m.id=='fixture-memory').likedByMe,isTrue); await back(t);
    await key(t,'memoriesPlacesButton'); await key(t,'placesAddButton');
    await enter(t,'placeName','Тэрэлж'); await enter(t,'placeLatitude','47.98'); await enter(t,'placeLongitude','107.46');
    FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle(); await key(t,'savePlaceButton');
    expect(controller.data.places,hasLength(1)); await shot(t,'09-places'); await back(t);
    await tab(t,'Нүүр'); await key(t,'homeIdeasButton'); await shot(t,'10-ideas');
    await tap(t,find.text('Кофе, бас яриа').first); await shot(t,'11-idea-detail');
    await tap(t,find.text('Урилга бүтээх')); await enter(t,'inviteRecipient','Тэмүүлэн'); await enter(t,'inviteSender','Ану'); await enter(t,'invitePlace','Little Heaven');
    FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle(); await shot(t,'13-invitation-editor');
    await tap(t,find.text('Урилгаа харах')); await shot(t,'14-invitation-preview'); expect(controller.data.gifts.invitations,hasLength(1));
    // Return to root via navigator, then inspect persistent invitation list.
    final nav=Navigator.of(t.element(find.byType(InvitationPreview)));
    nav.popUntil((route)=>route.isFirst); await t.pumpAndSettle();
    await tab(t,'Бэлэг'); await shot(t,'16-flowers');
    await tap(t,find.text('Урилгууд').first); await shot(t,'12-invitations');
    await tab(t,'Нүүр'); await key(t,'homeFlowerButton');
    await enter(t,'flowerRecipient','Тэмүүлэн'); await enter(t,'flowerSender','Ану'); await enter(t,'flowerMessage','Чамтай өдөр бүр илүү гоё.');
    FocusManager.instance.primaryFocus?.unfocus(); await t.pumpAndSettle(); await shot(t,'17-flower-editor');
    await tap(t,find.text('Мэндчилгээгээ харах')); await shot(t,'18-flower-preview');
    await tap(t,find.text('Дурсамждаа хадгалах'));
    final saved=controller.data.memories.firstWhere((m)=>m.id.startsWith('flower_'));
    expect(await File(saved.photoPath!).exists(),isTrue); expect(await File(saved.photoPath!).length(),greaterThan(1000));
    final loaded=await store.read(); expect(loaded.events,hasLength(1));expect(loaded.memories,hasLength(3));expect(loaded.places,hasLength(1));expect(loaded.gifts.invitations,hasLength(1));
    final invite=DateInvitation(id:'recipient-demo',templateId:'coffee',title:'Кофе уух уу?',recipientName:'Ану',senderName:'Тэмүүлэн',startsAt:DateTime.now().add(const Duration(days:2)),createdAt:DateTime.now(),place:'Little Heaven',state:InvitationState.pending,creatorId:'creator-fixture',recipientId:'recipient-fixture');
    await t.pumpWidget(MaterialApp(theme:buildAppTheme(),home:InvitationRecipientScreen(controller:controller,gateway:RecipientGateway(),invitation:invite)));
    await t.pumpAndSettle(); await shot(t,'15-recipient'); await tap(t,find.text('Тэгье ♡'));expect(find.text('Зөвшөөрсөн'),findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink()); controller.dispose();
    await File(saved.photoPath!).delete(); await dir.delete(recursive:true);
    expect(t.takeException(),isNull);
  });
}

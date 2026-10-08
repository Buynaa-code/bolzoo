import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamtdaa/content/content_repository.dart';
import 'package:hamtdaa/data/app_controller.dart';
import 'package:hamtdaa/features/calendar/calendar_screen.dart';
import 'package:hamtdaa/ui/theme.dart';

class CalendarRepository extends Fake implements ContentRepository {
  final records=<String,ContentItem>{};
  bool? savedShared;
  @override String get userId=>'me';
  ContentItem record(String id,String title,{bool partner=false,bool shared=false,String status='pending'}) => ContentItem.fromJson({
    'id':id,'kind':'event','owner_id':partner?'partner':'me','owner_name':partner?'Хос':'Би','pair_id':shared?'pair':null,'version':1,'revision':1,'state':'active','role':partner?'partner':'owner','updated_at':DateTime.now().toIso8601String(),
    'payload':{'title':title,'startsAt':DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day,18).toIso8601String(),'createdAt':DateTime.now().toIso8601String(),'place':'Кафе','note':'Ярилцъя','status':status}});
  @override Future<List<ContentItem>> snapshot() async => records.values.toList();
  @override Future<ContentItem> save({required String commandId,required String id,required String kind,required Map<String,Object?> payload,required bool shared,int? expectedVersion}) async {
    savedShared=shared;
    return records[id]=ContentItem.fromJson({'id':id,'kind':kind,'owner_id':'me','owner_name':'Би','pair_id':shared?'pair':null,'version':1,'revision':1,'state':'active','role':'owner','updated_at':DateTime.now().toIso8601String(),'payload':{...payload,'status':shared?'pending':'active'}});
  }
  @override Future<ContentItem> respond({required String commandId,required String id,required int expectedVersion,required String action,DateTime? proposedAt}) async => records[id]=record(id,records[id]!.payload['title'] as String,partner:true,shared:true,status:'accepted');
}
Future<void> _pump(WidgetTester t,Widget child) async {t.view.devicePixelRatio=1;t.view.physicalSize=const Size(390,844);addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);await t.pumpWidget(MaterialApp(theme:buildAppTheme(),home:Scaffold(body:child)));await t.pumpAndSettle();}
Future<void> _finish(WidgetTester t,AppController c) async {await t.pumpWidget(const SizedBox.shrink());c.dispose();await t.pumpAndSettle();}
void main() {
  testWidgets('calendar filters expose actual ownership and sharing', (t) async {
    final repo=CalendarRepository();repo.records.addAll({'mine':repo.record('mine','Миний кофе'),'ours':repo.record('ours','Бидний кино',shared:true),'theirs':repo.record('theirs','Хосын алхалт',partner:true,shared:true)});
    final c=AppController(MemoryAppStore());await c.load();c.connectCloud(repo);await _pump(t,CalendarScreen(controller:c));
    expect(find.text('2 төлөвлөгөө'),findsOneWidget);
    await t.tap(find.byKey(const Key('calendarFilter1')));await t.pumpAndSettle();expect(find.text('1 төлөвлөгөө'),findsOneWidget);
    await t.tap(find.byKey(const Key('calendarFilter2')));await t.pumpAndSettle();expect(find.text('2 төлөвлөгөө'),findsOneWidget);
    await _finish(t,c);
  });
  testWidgets('shared event editor saves actual server visibility and waits for consent', (t) async {
    final repo=CalendarRepository();final c=AppController(MemoryAppStore());await c.load();c.connectCloud(repo);await _pump(t,CalendarScreen(controller:c));
    await t.tap(find.byKey(const Key('calendarAddEvent')));await t.pumpAndSettle();await t.enterText(find.byKey(const Key('eventTitle')),'Шинэ болзоо');
    final share=find.byKey(const Key('eventShared'));await t.scrollUntilVisible(share,250,scrollable:find.byType(Scrollable).last);await t.tap(share);await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('saveEventButton')));await t.pumpAndSettle();expect(repo.savedShared,isTrue);expect(c.data.events.single.shared,isTrue);expect(c.consentState(c.data.events.single.id),'pending');await _finish(t,c);
  });
  testWidgets('partner detail cannot edit owner content and acceptance is authoritative', (t) async {
    final repo=CalendarRepository();repo.records['partner']=repo.record('partner','Кофе уух уу?',partner:true,shared:true);final c=AppController(MemoryAppStore());await c.load();c.connectCloud(repo);
    await _pump(t,Builder(builder:(context)=>TextButton(onPressed:()=>openEventDetail(context,c,'partner'),child:const Text('Нээх'))));await t.tap(find.text('Нээх'));await t.pumpAndSettle();
    expect(find.byTooltip('Төлөвлөгөө засах'),findsNothing);expect(find.text('Төлөвлөгөө устгах'),findsNothing);
    final accept=find.text('Зөвшөөрөх ♡');await t.scrollUntilVisible(accept,250,scrollable:find.byType(Scrollable).last);await t.tap(accept);await t.pumpAndSettle();expect(find.text('Хоёулаа тохирсон ♡'),findsOneWidget);
    c.setCloudForeground(false);await t.pumpAndSettle();expect(find.text('Энэ төлөвлөгөө байхгүй байна.'),findsOneWidget);await _finish(t,c);
  });
}

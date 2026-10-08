import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';

class Reminders {
  Reminders._();
  static final instance=Reminders._();
  final _plugin=FlutterLocalNotificationsPlugin();
  bool ready=false;
  ValueChanged<String>? onTap;
  String? pendingEventId;
  Future<void> initialize() async {
    if(ready || (!Platform.isIOS && !Platform.isAndroid)) return;
    await _plugin.initialize(settings:const InitializationSettings(
      android:AndroidInitializationSettings('ic_notification'),
      iOS:DarwinInitializationSettings(requestAlertPermission:false,requestBadgePermission:false,requestSoundPermission:false)),
      onDidReceiveNotificationResponse:(response) {
        final id=response.payload;
        if(id!=null) { pendingEventId=id; onTap?.call(id); }
      });
    final launch=await _plugin.getNotificationAppLaunchDetails();
    if(launch?.didNotificationLaunchApp == true) pendingEventId=launch?.notificationResponse?.payload;
    ready=true;
  }
  Future<bool> requestPermission() async {
    if(!ready) return false;
    if(Platform.isIOS) return await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert:true,badge:true,sound:true) ?? false;
    return await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
  }
  Future<void> sync(List<DateEvent> events) async {
    if(!ready) return;
    // Replace the account's queue. iOS supports at most64 pending notifications.
    await _plugin.cancelAllPendingNotifications();
    final upcoming=events.where((e)=>e.reminderMinutes>0 && e.startsAt.subtract(Duration(minutes:e.reminderMinutes)).isAfter(DateTime.now())).toList()..sort((a,b)=>a.startsAt.compareTo(b.startsAt));
    var id=1;
    for(final event in upcoming.take(60)) {
      await _plugin.zonedSchedule(id:id++,title:'Болзооны сануулга',body:event.title,
        scheduledDate:tz.TZDateTime.from(event.startsAt.subtract(Duration(minutes:event.reminderMinutes)).toUtc(),tz.UTC),
        notificationDetails:const NotificationDetails(android:AndroidNotificationDetails('date_reminders','Болзооны сануулга',channelDescription:'Таны сонгосон болзооны сануулгууд',importance:Importance.high),iOS:DarwinNotificationDetails()),
        androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,payload:event.id);
    }
  }
  Future<void> clear() async { if(ready) await _plugin.cancelAll(); }
}

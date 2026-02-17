import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> initializeWebNotifications() async {
  await web.Notification.requestPermission().toDart;
  // permission es un String ('granted', 'denied', 'default')
}

Future<void> showWebNotification(String title, String body) async {
  if (web.Notification.permission == 'granted') {
    web.Notification(title, web.NotificationOptions(body: body));
  }
}

Future<String> getWebNotificationPermission() async {
  return web.Notification.permission;
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'chat_controller.dart';
import 'shell_navigation.dart';

/// Android pop-ups (the system notification shade), the phone counterpart
/// of the desktop toasts (local_notifier). They show while the app is
/// running, in front or in the background; once Android has closed the app,
/// only a server push (Firebase) could wake it, which isn't set up.
///
/// Tapping one opens what it is about: a chat (payload `chat:<id>`, or
/// `chat:` for the chat list) or a screen (`screen:<nav key>`).
class PhoneNotifications {
  PhoneNotifications._();
  static final instance = PhoneNotifications._();

  static bool get supported => Platform.isAndroid;

  static const _chat = AndroidNotificationDetails(
    'chat', 'Chat messages',
    channelDescription: 'New messages in Hypermed chats',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );
  static const _general = AndroidNotificationDetails(
    'general', 'Notifications and email',
    channelDescription: 'Approvals, tasks and new email',
    importance: Importance.high,
    priority: Priority.high,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  int _nextId = 1;

  /// Safe to call repeatedly; asks for the notification permission once
  /// (Android 13+ shows the system prompt).
  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    if (!supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      // The app was opened by tapping a pop-up while it was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _open(launch!.notificationResponse?.payload);
    } catch (_) {}
  }

  Future<void> showChat(String title, String body, int? conversationId) =>
      _show(title, body, _chat, 'chat:${conversationId ?? ''}');

  Future<void> showGeneral(String title, String body, {String? screen}) =>
      _show(title, body, _general, screen == null ? null : 'screen:$screen');

  Future<void> _show(String title, String body, AndroidNotificationDetails details, String? payload) async {
    if (!supported) return;
    try {
      await init();
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: payload,
      );
    } catch (_) {}
  }

  void _open(String? payload) {
    if (payload == null) return;
    if (payload.startsWith('chat:')) {
      final id = int.tryParse(payload.substring(5));
      final c = ChatController.instance;
      c.openRequests.value = null;
      c.openRequests.value = id ?? -1;
    } else if (payload.startsWith('screen:')) {
      ShellNavigation.openScreen?.call(payload.substring(7));
    }
  }
}

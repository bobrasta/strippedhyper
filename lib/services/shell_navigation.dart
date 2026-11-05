import '../models/notification.dart';

/// Lets code outside the widget tree (desktop toast clicks) move the app
/// shell. Set by AppShell while it is mounted; null otherwise.
class ShellNavigation {
  ShellNavigation._();

  /// Opens the screen with this nav key (e.g. 'email').
  static void Function(String key)? openScreen;

  /// Opens wherever a notification's recipient acts on it — the bell's
  /// own routing.
  static void Function(AppNotification notification)? openNotification;
}

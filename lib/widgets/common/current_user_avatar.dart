import 'package:flutter/material.dart';
import '../../main.dart' show userNameNotifier, userAvatarUrlNotifier, nameInitials;
import 'avatar_widget.dart';

/// The logged-in user's avatar for the app shell (top bar, sidebar, rail):
/// their profile photo when they have one, initials otherwise. Rebuilds on
/// name or photo changes, so an upload in Settings shows up everywhere.
class CurrentUserAvatar extends StatelessWidget {
  const CurrentUserAvatar({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([userNameNotifier, userAvatarUrlNotifier]),
    builder: (_, _) => AvatarWidget(
      initials: nameInitials(userNameNotifier.value),
      size: size,
      variant: AvatarVariant.teal,
      imageUrl: userAvatarUrlNotifier.value,
    ),
  );
}

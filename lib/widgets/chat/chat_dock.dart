import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/chat_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'chat_panel.dart';

/// Desktop and tablet: a round chat button in the bottom-right corner that
/// opens a docked chat window over the page, Messenger-style. The page
/// stays usable behind it: the window doesn't close when you click
/// elsewhere, and minimising it brings the button back.
class ChatDock extends StatefulWidget {
  const ChatDock({super.key});

  @override
  State<ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends State<ChatDock> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    ChatController.instance.openRequests.addListener(_onOpenRequest);
  }

  @override
  void dispose() {
    ChatController.instance.openRequests.removeListener(_onOpenRequest);
    super.dispose();
  }

  // A desktop pop-up was clicked: open the window (the panel then opens the chat).
  void _onOpenRequest() {
    // The Chats screen, when it is open, takes the request itself.
    if (ChatController.instance.openRequests.value != null && !_open && !chatScreenOpenNotifier.value) {
      setState(() => _open = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      right: 20,
      bottom: 20,
      child: ListenableBuilder(
        listenable: Listenable.merge([chatAvailableNotifier, chatScreenOpenNotifier]),
        // Hidden on servers without chat, and on the Chats screen itself.
        builder: (_, _) => !chatAvailableNotifier.value || chatScreenOpenNotifier.value ? const SizedBox.shrink() : _open
          ? Container(
              width: math.min(380, size.width - 40),
              height: math.min(560, size.height - 120),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.pal.surface1,
                borderRadius: BorderRadius.circular(AppColors.rMd),
                border: Border.all(color: context.pal.borderStrong),
                boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 40, offset: Offset(0, 12))],
              ),
              child: Material(
                color: Colors.transparent,
                child: ChatPanel(onClose: () => setState(() => _open = false)),
              ),
            )
          : _ChatFab(onTap: () => setState(() => _open = true)),
      ),
    );
  }
}

class _ChatFab extends StatelessWidget {
  const _ChatFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Chats',
        child: Material(
          color: AppColors.teal,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: AppColors.tealGlow,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(clipBehavior: Clip.none, children: [
                const Center(child: Icon(Symbols.chat, size: 22, fill: 1, color: Color(0xFF06120F))),
                Positioned(top: -2, right: -2, child: const ChatUnreadBadge()),
              ]),
            ),
          ),
        ),
      );
}

/// The unread count on the chat button / top-bar icon; hidden at 0.
class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: chatUnreadNotifier,
        builder: (_, n, _) => n <= 0
            ? const SizedBox.shrink()
            : Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.coral,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.pal.surface1, width: 1.5),
                ),
                child: Text(n > 99 ? '99+' : '$n', textAlign: TextAlign.center, maxLines: 1,
                    style: const TextStyle(fontFamily: 'TildaSans', fontSize: 10.5, fontWeight: FontWeight.w700,
                        height: 1.3, color: Colors.white)),
              ),
      );
}

/// Phone: chat opens as its own full-screen page.
Future<void> openChatFullScreen(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.pal.bg,
          body: SafeArea(child: ChatPanel(
            onClose: () => Navigator.of(ctx).pop(),
            closeIcon: Symbols.close,
          )),
        ),
      ),
    );

/// The Chats menu entry's unread pill (same look as the Email entry's).
class ChatNavBadge extends StatelessWidget {
  const ChatNavBadge({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: chatUnreadNotifier,
        builder: (_, n, _) => n <= 0
            ? const SizedBox.shrink()
            : Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(999)),
                child: Text(n > 99 ? '99+' : '$n', textAlign: TextAlign.center, maxLines: 1,
                    style: const TextStyle(fontFamily: 'TildaSans', fontSize: 11, fontWeight: FontWeight.w700,
                        height: 1.3, color: Color(0xFF06120F))),
              ),
      );
}

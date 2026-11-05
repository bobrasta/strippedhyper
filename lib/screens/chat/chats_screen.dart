import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/chat_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat/chat_panel.dart';

/// The Chats menu screen: the chat list beside the open chat (one pane at a
/// time on a phone). Same chats as the floating chat window, which hides
/// while this screen is open.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  @override
  void initState() {
    super.initState();
    // After the frame: the dock listens to this (no notifying mid-build).
    WidgetsBinding.instance.addPostFrameCallback((_) => chatScreenOpenNotifier.value = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => chatScreenOpenNotifier.value = false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: chatAvailableNotifier,
        builder: (context, available, _) => available
            ? Container(
                color: context.pal.surface1,
                child: const ChatPanel(workspace: true),
              )
            : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.forum, size: 40, color: context.pal.textDim),
                const SizedBox(height: 12),
                Text('Chat is not available on this server yet.', style: AppTheme.bodySub),
              ])),
      );
}

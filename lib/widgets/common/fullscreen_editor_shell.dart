import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';

/// Shared chrome for a node editor's "maximize" mode — rendered into an
/// [OverlayEntry] by the caller so the same live State (nodes, drag
/// positions, selection) keeps running, just presented full-window instead
/// of inline. Used by both OrgChartEditor and RolesGraphView.
class FullscreenEditorShell extends StatelessWidget {
  const FullscreenEditorShell({
    super.key,
    required this.title,
    required this.onClose,
    required this.toolbar,
    required this.child,
    this.error,
  });

  final String title;
  final VoidCallback onClose;
  final Widget toolbar;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: context.pal.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.pal.borderStrong),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.pal.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, style: AppTheme.pageTitle.copyWith(fontSize: 16))),
                    IconButton(
                      onPressed: onClose,
                      icon: Icon(Symbols.close, color: context.pal.textMute),
                      tooltip: 'Close',
                    ),
                  ]),
                  const SizedBox(height: 10),
                  toolbar,
                ]),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(error!, style: AppTheme.bodySub.copyWith(color: Colors.redAccent)),
                ),
              Expanded(child: Padding(padding: const EdgeInsets.all(16), child: child)),
            ]),
          ),
        ),
      ),
    );
  }
}

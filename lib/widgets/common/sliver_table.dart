import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A list-page table as slivers, for a page that scrolls as one piece
/// (summary cards, then the table): the column [header] pins to the top while
/// rows scroll, rows are built lazily, and [footer] closes the card at the end.
/// Keeps the usual card look (surface1, border, 14px corners).
List<Widget> sliverTable(
  BuildContext context, {
  required double pad,
  required Widget header,
  required double headerHeight,
  required int itemCount,
  required Widget Function(BuildContext context, int index) itemBuilder,
  Widget? footer,
  String emptyText = 'Nothing found',
  /// Set when only the first [itemCount] of [totalCount] rows are shown;
  /// adds a "Load more" row under the last one.
  int? totalCount,
  int loadStep = 100,
  VoidCallback? onLoadMore,
}) {
  final side = BorderSide(color: context.pal.border);
  final pinned = ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
    child: Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(top: side, left: side, right: side, bottom: BorderSide(color: context.pal.divider)),
      ),
      child: header,
    ),
  );
  return [
    SliverPersistentHeader(pinned: true, delegate: _PinnedHeader(height: headerHeight + 2, pad: pad, child: pinned)),
    SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      sliver: itemCount == 0
          ? SliverToBoxAdapter(child: Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: context.pal.surface1, border: Border(left: side, right: side)),
              child: Text(emptyText, style: AppTheme.bodySub),
            ))
          : SliverList(delegate: SliverChildBuilderDelegate(
              (ctx, i) => Container(
                decoration: BoxDecoration(
                  color: context.pal.surface1,
                  border: Border(left: side, right: side, bottom: BorderSide(color: context.pal.divider)),
                ),
                child: itemBuilder(ctx, i),
              ),
              childCount: itemCount,
            )),
    ),
    if (onLoadMore != null && totalCount != null && totalCount > itemCount)
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        sliver: SliverToBoxAdapter(child: LoadMoreRow(
          shown: itemCount, total: totalCount, step: loadStep, onTap: onLoadMore)),
      ),
    SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
      sliver: SliverToBoxAdapter(child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border(left: side, right: side, bottom: side),
          ),
          child: footer ?? const SizedBox(height: 8),
        ),
      )),
    ),
  ];
}

/// "Showing X of Y · Load N more" row for a table that renders its rows in
/// batches (the data is already loaded; this only limits rows built).
class LoadMoreRow extends StatelessWidget {
  const LoadMoreRow({super.key, required this.shown, required this.total, required this.step, required this.onTap});
  final int shown, total, step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: context.pal.border);
    final next = total - shown < step ? total - shown : step;
    return Material(
      color: context.pal.surface1,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48, alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(left: side, right: side, bottom: BorderSide(color: context.pal.divider))),
          child: Text('Showing $shown of $total · Load $next more',
              style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: AppColors.teal)),
        ),
      ),
    );
  }
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.pad, required this.child});
  final double height, pad;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: context.pal.bg, padding: EdgeInsets.symmetric(horizontal: pad), child: child);
  @override
  bool shouldRebuild(_PinnedHeader old) => old.child != child || old.pad != pad || old.height != height;
}

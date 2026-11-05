import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme/app_palette.dart';

/// A single shimmer-animated placeholder block.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = context.pal.isDark ? context.pal.border : context.pal.surface3;
    final high = context.pal.isDark
        ? const Color(0xFF2E3C52)
        : context.pal.surface1;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: high,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Shimmer skeleton for a list-style row (icon + two text lines + badge).
/// Matches the shape used by ticket list, hospital list, and contact list rows.
class ShimmerListRow extends StatelessWidget {
  const ShimmerListRow({super.key, this.height = 64});
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = context.pal.isDark ? context.pal.border : context.pal.surface3;
    final high = context.pal.isDark
        ? const Color(0xFF2E3C52)
        : context.pal.surface1;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: high,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Avatar / icon circle
          _pill(base, width: 36, height: 36, radius: 18),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pill(base, height: 13),
                const SizedBox(height: 6),
                _pill(base, height: 11, width: 180),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Status badge
          _pill(base, width: 64, height: 22, radius: 10),
        ]),
      ),
    );
  }
}

/// Shimmer skeleton for a table-style row (several column placeholders).
/// Matches the shape used by machine list, spare parts, and revenue tables.
class ShimmerTableRow extends StatelessWidget {
  const ShimmerTableRow({super.key, this.cols = 5});
  final int cols;

  @override
  Widget build(BuildContext context) {
    final base = context.pal.isDark ? context.pal.border : context.pal.surface3;
    final high = context.pal.isDark
        ? const Color(0xFF2E3C52)
        : context.pal.surface1;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: high,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          for (int i = 0; i < cols; i++) ...[
            Expanded(child: _pill(base, height: 13)),
            if (i < cols - 1) const SizedBox(width: 16),
          ],
        ]),
      ),
    );
  }
}

/// Returns a column of [count] shimmer list rows — drop-in replacement for a
/// `CircularProgressIndicator` inside a list/table loading state.
Widget shimmerList({int count = 8}) => _clippedSkeleton(
      List.generate(count, (_) => const ShimmerListRow()),
    );

Widget shimmerTable({int count = 8, int cols = 5}) => _clippedSkeleton(
      List.generate(count, (_) => ShimmerTableRow(cols: cols)),
    );

/// Skeleton rows that never overflow: in a bounded box (a short phone
/// viewport) the rows past the bottom are clipped; inside a scroll view
/// (unbounded) they lay out in full as before.
Widget _clippedSkeleton(List<Widget> rows) => LayoutBuilder(
      builder: (_, cst) {
        final column = Column(children: rows);
        if (!cst.hasBoundedHeight) return column;
        return ClipRect(child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: column,
        ));
      },
    );

// Internal helper — a solid pill/rectangle for building skeletons
Widget _pill(Color color, {double? width, required double height, double radius = 6}) =>
    Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

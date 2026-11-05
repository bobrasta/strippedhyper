import 'package:flutter/widgets.dart';

/// MaterializeCSS-inspired 12-column responsive grid for Flutter.
///
/// Content-area breakpoints (width of the widget, not the screen):
///   narrow  < 700 px   (small desktop / tablet)
///   medium  700–1100 px
///   wide    ≥ 1100 px  (full desktop)
///
/// Usage — column-width helper (mirrors wdetermine.dart, bug-fixed):
/// ```dart
/// LayoutBuilder(builder: (ctx, cst) {
///   final w = Responsive.colWidth('l6', 'm12', 's12', cst);
///   return SizedBox(width: w, child: ...);
/// })
/// ```
///
/// Usage — adaptive grid row:
/// ```dart
/// ResponsiveRow(
///   children: [CardA(), CardB(), CardC(), CardD()],
///   minChildWidth: 200, // collapse to wrap when each child < 200 px
/// )
/// ```
enum ScreenBreak { narrow, medium, wide }

class Responsive {
  Responsive._();

  static const double _medium = 700;
  static const double _wide   = 1100;

  // ── Breakpoint detection ──────────────────────────────────────────────────

  /// Current break for an available [width] (e.g. from LayoutBuilder).
  static ScreenBreak breakFor(double width) {
    if (width < _medium) return ScreenBreak.narrow;
    if (width < _wide)   return ScreenBreak.medium;
    return ScreenBreak.wide;
  }

  /// Current break using [MediaQuery] screen width.
  static ScreenBreak breakOf(BuildContext context) =>
      breakFor(MediaQuery.sizeOf(context).width);

  static bool isNarrow(double width)  => width < _medium;
  static bool isMedium(double width)  => width >= _medium && width < _wide;
  static bool isWide(double width)    => width >= _wide;

  // ── Column-width helper ───────────────────────────────────────────────────

  /// Returns a pixel width for a column slot, identical in spirit to
  /// [Determine.lastwidth] in wdetermine.dart — but with the bug fixed
  /// (original m11/s11 multiplied by 91.67 instead of 0.9167).
  ///
  /// [wide], [medium], [small] are Materialize-style column strings:
  ///   'l6' = 6/12 = 50% at wide,  'm8' = 8/12 at medium,  's12' = full at narrow.
  static double colWidth(
    String wide, String medium, String small,
    BoxConstraints constraints,
  ) {
    final k    = constraints.maxWidth;
    final col  = switch (breakFor(k)) {
      ScreenBreak.wide   => wide,
      ScreenBreak.medium => medium,
      ScreenBreak.narrow => small,
    };
    return k * _fraction(col);
  }

  /// Pick one value out of three depending on the current break.
  static T value<T>(
    BoxConstraints constraints, {
    required T wide,
    T? medium,
    required T narrow,
  }) => switch (breakFor(constraints.maxWidth)) {
    ScreenBreak.wide   => wide,
    ScreenBreak.medium => medium ?? wide,
    ScreenBreak.narrow => narrow,
  };

  // ── Private ───────────────────────────────────────────────────────────────

  static double _fraction(String col) {
    final n = int.tryParse(col.replaceAll(RegExp('[lms]'), '')) ?? 12;
    return (n.clamp(1, 12)) / 12.0;
  }
}

// ── ResponsiveRow ─────────────────────────────────────────────────────────────

/// Renders children in a [Row] when the available width is sufficient,
/// or in a [Wrap] when it would be too cramped.
///
/// Set [minChildWidth] to the minimum acceptable per-child pixel width.
/// When `availableWidth / children.length < minChildWidth`, it wraps.
///
/// [spacing] applies horizontally in Row mode and [runSpacing] between rows
/// in Wrap mode.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.minChildWidth = 160,
    this.spacing       = 16.0,
    this.runSpacing    = 12.0,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.stretchRow    = true,
  });

  final List<Widget> children;
  final double minChildWidth;
  final double spacing;
  final double runSpacing;
  final CrossAxisAlignment crossAxisAlignment;
  /// When true, Row children are wrapped in [Expanded] automatically.
  final bool stretchRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final totalGaps    = spacing * (children.length - 1);
      final perChild     = (constraints.maxWidth - totalGaps) / children.length;

      if (perChild < minChildWidth) {
        // Wrap mode — each child is already sized or uses full width
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((c) => SizedBox(
            width: constraints.maxWidth,
            child: c,
          )).toList(),
        );
      }

      // Row mode
      final rowChildren = <Widget>[];
      for (int i = 0; i < children.length; i++) {
        rowChildren.add(stretchRow ? Expanded(child: children[i]) : children[i]);
        if (i < children.length - 1) rowChildren.add(SizedBox(width: spacing));
      }
      return Row(
        crossAxisAlignment: crossAxisAlignment,
        children: rowChildren,
      );
    });
  }
}

// ── AdaptiveColumns ───────────────────────────────────────────────────────────

/// Renders a fixed list of widgets in a multi-column grid that collapses
/// from [wideCols] → [mediumCols] → [narrowCols] as width decreases.
///
/// Children that don't fill the last row get an empty [SizedBox].
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.children,
    this.wideCols   = 4,
    this.mediumCols = 2,
    this.narrowCols = 1,
    this.spacing    = 16.0,
    this.runSpacing = 12.0,
  });

  final List<Widget> children;
  final int wideCols, mediumCols, narrowCols;
  final double spacing, runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = switch (Responsive.breakFor(constraints.maxWidth)) {
        ScreenBreak.wide   => wideCols,
        ScreenBreak.medium => mediumCols,
        ScreenBreak.narrow => narrowCols,
      };
      final cellWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children.map((c) => SizedBox(width: cellWidth, child: c)).toList(),
      );
    });
  }
}

// ── HScrollTable ──────────────────────────────────────────────────────────────

/// Wraps a table-like widget in a horizontal scroll when the content
/// would overflow, while keeping it at natural width when there is room.
class HScrollTable extends StatelessWidget {
  const HScrollTable({
    super.key,
    required this.child,
    this.minWidth = 800,
  });

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= minWidth) {
        return child;
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minWidth, child: child),
      );
    });
  }
}

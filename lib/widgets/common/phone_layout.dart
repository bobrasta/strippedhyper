import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'app_button.dart';

/// Content-area width below which list screens switch to their phone layout
/// (cards instead of tables, detail as its own page, stacked header).
const double kPhoneBreakpoint = 600;

bool isPhoneWidth(double width) => width < kPhoneBreakpoint;

/// A header action: the primary one becomes a button, the rest go behind an
/// icon (one action) or a ⋮ menu (several).
class PageAction {
  const PageAction({required this.label, required this.icon, required this.onPressed, this.shortLabel});
  final String label;
  /// Label for the phone button when [label] is too long ("New Order" → "New").
  final String? shortLabel;
  final IconData icon;
  final VoidCallback? onPressed;
}

/// Phone version of a list screen's header:
///
///   Title                      [⋮] [+ New]
///   subtitle
///   [ search ……………………………………………… ]
///   (All) (Open) (Closed) …  ← one swipeable line
///
/// Each screen keeps its own desktop header and uses this below
/// [kPhoneBreakpoint], so desktop layouts are unchanged.
class PhonePageHeader extends StatelessWidget {
  const PhonePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.primary,
    this.secondary = const [],
    this.search,
    this.filters = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final PageAction? primary;
  final List<PageAction> secondary;
  /// Full-width search field (pass a SearchField without a width).
  final Widget? search;
  /// Chips / dropdowns, laid out on one horizontally scrolling line.
  final List<Widget> filters;
  /// Anything else under the filters (e.g. a screen's own chip strip that
  /// already scrolls by itself).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTheme.pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTheme.bodySub, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ])),
        if (secondary.length == 1)
          IconButton(
            tooltip: secondary.first.label,
            onPressed: secondary.first.onPressed,
            icon: Icon(secondary.first.icon, size: 20, color: context.pal.textMute),
          )
        else if (secondary.length > 1)
          PopupMenuButton<int>(
            tooltip: 'More actions',
            color: context.pal.surface1,
            icon: Icon(Symbols.more_vert, size: 20, color: context.pal.textMute),
            onSelected: (i) => secondary[i].onPressed?.call(),
            itemBuilder: (_) => [
              for (final (i, a) in secondary.indexed)
                PopupMenuItem(value: i, enabled: a.onPressed != null, child: Row(children: [
                  Icon(a.icon, size: 18, color: context.pal.textMute),
                  const SizedBox(width: 12),
                  Text(a.label, style: AppTheme.bodySm),
                ])),
            ],
          ),
        if (primary != null) ...[
          const SizedBox(width: 4),
          AppButton(
            label: primary!.shortLabel ?? primary!.label,
            icon: primary!.icon,
            variant: BtnVariant.primary,
            onPressed: primary!.onPressed,
          ),
        ],
      ]),
      if (search != null) ...[
        const SizedBox(height: 10),
        search!,
      ],
      if (filters.isNotEmpty) ...[
        const SizedBox(height: 10),
        PhoneScrollRow(children: filters),
      ],
      if (bottom != null) ...[
        const SizedBox(height: 10),
        bottom!,
      ],
    ]),
  );
}

/// One swipeable line of chips/controls — replaces a [Wrap] that would take
/// two or three rows of a phone screen.
class PhoneScrollRow extends StatelessWidget {
  const PhoneScrollRow({super.key, required this.children, this.spacing = 6});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(width: spacing),
        c,
      ],
    ]),
  );
}

/// A record as a phone card — the phone stand-in for one table row:
///
///   [lead]  Title                         [badge]
///           subtitle
///           meta · meta · meta              amount
class PhoneRecordCard extends StatelessWidget {
  const PhoneRecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.lead,
    this.badge,
    this.meta = const [],
    this.amount,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  /// Outside spacing; pass `EdgeInsets.only(bottom: 8)` inside padded pages.
  final EdgeInsetsGeometry margin;
  final String title;
  final String? subtitle;
  /// Small leading visual (icon tile, avatar).
  final Widget? lead;
  /// Status pill, top-right.
  final Widget? badge;
  /// Short facts shown on the last line, joined with " · ".
  final List<String> meta;
  /// Emphasised value, bottom-right (a total, a quantity).
  final String? amount;
  final bool selected;
  final VoidCallback? onTap;
  /// Replaces [amount] when a widget is needed (e.g. a ⋮ menu).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final metaText = meta.where((m) => m.trim().isNotEmpty).join('  ·  ');
    return Padding(
      padding: margin,
      child: Material(
        color: selected ? context.pal.surface2 : context.pal.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.teal.withValues(alpha: 0.5) : context.pal.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (lead != null) ...[lead!, const SizedBox(width: 12)],
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(title, style: AppTheme.bodyStrong.copyWith(fontSize: 14),
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (badge != null) ...[const SizedBox(width: 8), badge!],
                ]),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: AppTheme.bodySub.copyWith(fontSize: 12.5),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (metaText.isNotEmpty || amount != null || trailing != null) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: Text(metaText,
                        style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if (trailing != null) trailing!
                    else if (amount != null) ...[
                      const SizedBox(width: 8),
                      Text(amount!, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                    ],
                  ]),
                ],
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Opens [panel] — a screen's existing desktop detail panel — as its own
/// page inside the content area, so back returns to the list where it was.
/// The panel's own close button should pop (pass `() => Navigator.pop(ctx)`).
Future<void> pushPhoneDetail(BuildContext context, Widget Function(BuildContext ctx) panel) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => Scaffold(
      backgroundColor: ctx.pal.bg,
      body: panel(ctx),
    )));

/// Small coloured status pill used on phone cards.
class PhonePill extends StatelessWidget {
  const PhonePill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: AppTheme.bodySub.copyWith(
        fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

/// KPI/stat tiles two to a row — the phone form of a 4-up stat strip.
class PhoneStatGrid extends StatelessWidget {
  const PhoneStatGrid({super.key, required this.children, this.spacing = 0});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cst) {
    final w = (cst.maxWidth - spacing) / 2;
    return Wrap(spacing: spacing, runSpacing: spacing, children: [
      for (final c in children) SizedBox(width: w.floorToDouble(), child: c),
    ]);
  });
}

/// Side-by-side panels on wide screens, stacked on phones. Pass the wide
/// layout's children as-is (Expanded panels with SizedBox gaps): on phones
/// each Expanded is unwrapped and each horizontal gap becomes a 12 px one.
Widget sideBySideOrStacked(bool phone, List<Widget> children) {
  if (!phone) {
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final c in children)
      if (c is Expanded) c.child
      else if (c is SizedBox && c.height == null) const SizedBox(height: 12)
      else c,
  ]);
}

/// A page title with its action buttons: beside the title on wide screens,
/// on their own wrapping line under it on phones (so the title never gets
/// squeezed to a few letters per line).
class TitleWithActions extends StatelessWidget {
  const TitleWithActions({super.key, required this.title, this.leading, this.actions = const []});

  /// The title block (title + subtitle column). Not wrapped in Expanded.
  final Widget title;
  /// Optional accent bar / icon before the title.
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cst) {
    final head = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (leading != null) ...[leading!, const SizedBox(width: 13)],
      Expanded(child: title),
      if (!isPhoneWidth(cst.maxWidth))
        for (final a in actions) ...[const SizedBox(width: 8), a],
    ]);
    if (!isPhoneWidth(cst.maxWidth) || actions.isEmpty) return head;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
    ]);
  });
}

/// On phones, shrinks [child] (a row of figures) to fit instead of
/// overflowing; elsewhere returns it untouched.
Widget fitOnPhone(bool phone, Widget child) => phone
    ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child)
    : child;

/// Wraps the card of an in-screen modal (dimmed backdrop + centred card).
/// On phones the card docks to the bottom like a sheet, never taller than
/// the screen; the backdrop above it still closes the modal. Elsewhere it's
/// a no-op.
///
/// [scroll]: true for cards that don't scroll by themselves — they get a
/// scroll view so a long form (or the keyboard) can't push them off-screen.
/// Pass false for cards with their own scrolling body: they get a height
/// limit instead, which their Flexible/Expanded body needs.
class PhoneModalBox extends StatelessWidget {
  const PhoneModalBox({super.key, required this.child, this.scroll = true});
  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cst) {
    if (!isPhoneWidth(cst.maxWidth)) return child;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: scroll
            ? SingleChildScrollView(padding: const EdgeInsets.only(bottom: 4), child: child)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: (cst.maxHeight - 28).clamp(0, double.infinity)),
                child: child,
              ),
      ),
    );
  });
}

/// A strip of equal stat tiles (each wrapped in Expanded) as one Row on
/// wide screens, or two to a row on phones (Expanded unwrapped).
Widget statStrip(bool phone, List<Widget> tiles) => phone
    ? PhoneStatGrid(children: [for (final t in tiles) t is Expanded ? t.child : t])
    : Row(children: tiles);

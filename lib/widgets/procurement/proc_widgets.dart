// Section 18/19 procurement widgets, from the Tenders & Shipments designs.
// Shared building blocks for Shipments (S18), Tenders & Device Registrations (S19).
// Only the pieces that repeat across ≥3 procurement screens live here.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../common/labeled_field.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

enum ProcTone { green, teal, amber, coral, violet, neutral }

extension ProcToneX on ProcTone {
  Color fg(BuildContext c) => switch (this) {
    ProcTone.green => AppColors.green,
    ProcTone.teal => AppColors.cyan,
    ProcTone.amber => AppColors.amber,
    ProcTone.coral => AppColors.coral,
    ProcTone.violet => AppColors.violet,
    ProcTone.neutral => c.pal.textMute,
  };
  Color bg(BuildContext c) => this == ProcTone.neutral
      ? c.pal.text.withValues(alpha: 0.06)
      : fg(c).withValues(alpha: 0.12);
}

TextStyle procMono(BuildContext c, {double size = 11, Color? color}) =>
    AppTheme.monoXs.copyWith(fontSize: size, color: color ?? c.pal.textDim);

TextStyle procCaps(BuildContext c, {Color? color}) => AppTheme.labelCaps.copyWith(
    fontSize: 10, letterSpacing: 1.1, color: color ?? c.pal.textDim);

/// Rule that fades out over 48px at each end (house style).
class FadeDivider extends StatelessWidget {
  const FadeDivider({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.pal.border;
    return LayoutBuilder(builder: (_, box) {
      final stop = box.maxWidth > 0 ? (48 / box.maxWidth).clamp(0.0, 0.5) : 0.0;
      return Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(
        colors: [c.withValues(alpha: 0), c, c, c.withValues(alpha: 0)],
        stops: [0, stop, 1 - stop, 1],
      )));
    });
  }
}

class ProcTag extends StatelessWidget {
  const ProcTag(this.label, {super.key, this.tone = ProcTone.neutral, this.small = false});
  final String label;
  final ProcTone tone;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 1 : 2),
    decoration: BoxDecoration(color: tone.bg(context), borderRadius: BorderRadius.circular(5)),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: AppTheme.bodySub.copyWith(fontSize: small ? 9.5 : 10.5, color: tone.fg(context))),
  );
}

/// Outlined action — primary actions are outlines, never fills.
class ProcButton extends StatelessWidget {
  const ProcButton({super.key, required this.label, this.icon, this.tone = ProcTone.neutral,
    this.onPressed, this.locked = false, this.large = false});
  final String label;
  final IconData? icon;
  final ProcTone tone;
  final VoidCallback? onPressed;
  final bool locked;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fg = locked ? pal.textDim : tone == ProcTone.neutral ? pal.textMute : tone.fg(context);
    final bd = locked ? pal.border : tone == ProcTone.neutral ? pal.border : tone.fg(context).withValues(alpha: 0.8);
    return Material(
      color: tone == ProcTone.neutral && !locked ? pal.surface1 : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: locked ? null : onPressed,
        borderRadius: BorderRadius.circular(9),
        hoverColor: tone.fg(context).withValues(alpha: 0.10),
        child: Container(
          height: large ? 36 : 30,
          padding: EdgeInsets.symmetric(horizontal: large ? 16 : 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: bd)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (locked) ...[Icon(Symbols.lock, size: 14, color: fg), const SizedBox(width: 6)]
            else if (icon != null) ...[Icon(icon, size: large ? 16 : 14, color: fg), const SizedBox(width: 6)],
            Text(label, style: AppTheme.bodySm.copyWith(fontSize: large ? 13 : 12, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// Page header: accent bar + optional breadcrumb, title, tag row, actions.
class ProcPageHeader extends StatelessWidget {
  const ProcPageHeader({super.key, required this.title, this.subtitle, this.breadcrumb,
    this.accent, this.tags = const [], this.actions = const []});
  final String title;
  final String? subtitle;
  final List<String>? breadcrumb;
  final Color? accent;
  final List<Widget> tags;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (breadcrumb != null) Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          for (var i = 0; i < breadcrumb!.length; i++) ...[
            if (i > 0) Icon(Symbols.chevron_right, size: 12, color: pal.textDim),
            Flexible(child: Text(breadcrumb![i], overflow: TextOverflow.ellipsis, style: i == 0
                ? AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textMute)
                : procMono(context))),
          ],
        ]),
      ),
      Text(title, style: AppTheme.pageTitle.copyWith(fontSize: 22, fontWeight: FontWeight.w500)),
      if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle!, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textDim))),
      if (tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: tags)),
    ]);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 13),
        child: narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                head, if (actions.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: actions)]])
            : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(width: 2, height: breadcrumb != null ? 52 : 38,
                    decoration: BoxDecoration(color: accent ?? AppColors.green, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 13),
                Expanded(child: head),
                Wrap(spacing: 8, children: actions),
              ]),
      ),
      const FadeDivider(),
    ]);
  }
}

/// Bordered panel with an uppercase header row — the unit of every detail page.
class ProcPanel extends StatelessWidget {
  const ProcPanel({super.key, required this.title, required this.icon, this.iconColor,
    this.trailing, required this.child, this.footer, this.borderColor, this.background, this.expand = false});
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;
  final Widget? footer;
  final Color? borderColor;
  final Color? background;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final body = Column(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.6)))),
        child: LayoutBuilder(builder: (context, box) => Row(children: [
          Icon(icon, size: 14, color: iconColor ?? pal.textMute),
          const SizedBox(width: 9),
          // Expanded, not Flexible + Spacer: those split the free space and
          // left [trailing] floating mid-header instead of at the right edge.
          Expanded(child: Text(title.toUpperCase(), style: procCaps(context, color: pal.textMute),
              overflow: TextOverflow.ellipsis)),
          // Capped so a long status tag ("Awaiting Finance (payment request)")
          // shortens on a phone instead of overflowing; wide screens have room.
          if (trailing != null) ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55), child: trailing),
        ])),
      ),
      expand ? Expanded(child: child) : child,
      if (footer != null) Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: pal.bg.withValues(alpha: 0.5),
            border: Border(top: BorderSide(color: pal.border.withValues(alpha: 0.6)))),
        child: footer,
      ),
    ]);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? pal.surface1,
        borderRadius: BorderRadius.circular(AppColors.rMd),
        border: Border.all(color: borderColor ?? pal.border),
      ),
      child: body,
    );
  }
}

/// Info footer line used inside panels.
class ProcNote extends StatelessWidget {
  const ProcNote(this.text, {super.key, this.icon = Symbols.info, this.tone = ProcTone.teal});
  final String text;
  final IconData icon;
  final ProcTone tone;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 14, color: tone.fg(context)),
    const SizedBox(width: 7),
    Expanded(child: Text(text, style: AppTheme.bodySub.copyWith(fontSize: 11,
        color: tone == ProcTone.amber ? AppColors.amber : context.pal.textMute))),
  ]);
}

class KpiStripItem {
  final IconData icon;
  final ProcTone tone;
  final String label, value, note;
  final bool alarm;
  const KpiStripItem(this.icon, this.tone, this.label, this.value, this.note, {this.alarm = false});
}

/// Joined KPI tiles in one bordered strip; wraps to 2×2 on narrow widths.
class KpiStrip extends StatelessWidget {
  const KpiStrip(this.items, {super.key});
  final List<KpiStripItem> items;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget tile(KpiStripItem k) => Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
      color: k.alarm ? AppColors.coral.withValues(alpha: 0.06) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(k.icon, size: 13, color: k.tone.fg(context), fill: k.alarm ? 1 : 0),
          const SizedBox(width: 7),
          Flexible(child: Text(k.label.toUpperCase(),
              style: procCaps(context, color: k.alarm ? AppColors.coral : null), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 9, children: [
          Text(k.value, style: AppTheme.kpiValue.copyWith(fontSize: 26, height: 1,
              color: k.alarm ? AppColors.coral : pal.text)),
          Padding(padding: const EdgeInsets.only(bottom: 2),
              child: Text(k.note, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
        ]),
      ]),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd),
          border: Border.all(color: pal.border)),
      child: LayoutBuilder(builder: (_, box) {
        if (box.maxWidth < 720) {
          return Wrap(children: [for (final k in items) SizedBox(width: box.maxWidth / 2, child: tile(k))]);
        }
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: pal.border.withValues(alpha: 0.7)),
            Expanded(child: tile(items[i])),
          ],
        ]));
      }),
    );
  }
}

class NeedsActionItem {
  final String? when;           // "2 days over" — tenders only
  final String ref, text, cta;
  final ProcTone tone;
  final VoidCallback? onTap;
  const NeedsActionItem({this.when, required this.ref, required this.text, required this.cta,
    this.tone = ProcTone.amber, this.onTap});
}

/// Amber-bordered "Needs action" panel, identical on Shipments and Tenders lists.
class NeedsActionPanel extends StatelessWidget {
  const NeedsActionPanel(this.items, {super.key, this.subtitle});
  final List<NeedsActionItem> items;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final amber = AppColors.amber;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppColors.rMd),
        border: Border.all(color: amber.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: amber.withValues(alpha: 0.14)))),
          child: Row(children: [
            Icon(Symbols.bolt, size: 14, color: amber, fill: 1),
            const SizedBox(width: 9),
            Text('NEEDS ACTION', style: procCaps(context, color: amber)),
            if (subtitle != null) ...[const SizedBox(width: 9),
              Flexible(child: Text(subtitle!, overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)))],
          ]),
        ),
        for (final a in items) InkWell(
          onTap: a.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: a.tone == ProcTone.coral ? AppColors.coral.withValues(alpha: 0.06) : null,
            child: Row(children: [
              Container(width: 3, height: 22, decoration: BoxDecoration(
                  color: a.tone.fg(context), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              if (a.when != null) SizedBox(width: 82, child: Text(a.when!, style: procMono(context, color: a.tone.fg(context)))),
              if (!narrow) SizedBox(width: a.when != null ? 170 : 110,
                  child: Text(a.ref, style: procMono(context, color: pal.textMute), overflow: TextOverflow.ellipsis)),
              Expanded(child: Text(narrow ? '${a.ref} · ${a.text}' : a.text,
                  style: AppTheme.bodySm.copyWith(fontSize: 12))),
              const SizedBox(width: 12),
              Text(a.cta, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: a.tone.fg(context))),
              const SizedBox(width: 4),
              Icon(Symbols.arrow_forward, size: 12, color: a.tone.fg(context)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Segmented progress bar — one segment per status step.
class StepBar extends StatelessWidget {
  const StepBar(this.colors, {super.key, this.height = 5});
  final List<Color> colors;
  final double height;
  @override
  Widget build(BuildContext context) => Row(children: [
    for (var i = 0; i < colors.length; i++) ...[
      if (i > 0) const SizedBox(width: 2),
      Expanded(child: Container(height: height,
          decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(2)))),
    ],
  ]);

  /// Standard colouring: done = green, current = [current], rest = off.
  static List<Color> segments(BuildContext c, {required int total, required int step, required Color current}) =>
      List.generate(total, (i) {
        final n = i + 1;
        return n < step ? AppColors.green : n == step ? current : c.pal.text.withValues(alpha: 0.08);
      });
}

class TimelineEntry {
  final String name;
  final String? date, note;
  final bool done, current;
  final Color? currentColor;
  const TimelineEntry(this.name, {this.date, this.note, this.done = false, this.current = false, this.currentColor});
}

/// Vertical status timeline with check dots.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline(this.entries, {super.key, this.compact = false});
  final List<TimelineEntry> entries;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final dot = compact ? 10.0 : 14.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < entries.length; i++) Builder(builder: (_) {
        final e = entries[i];
        final cc = e.currentColor ?? AppColors.cyan;
        final last = i == entries.length - 1;
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: dot + 2, child: Column(children: [
            const SizedBox(height: 2),
            Container(width: dot, height: dot,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: e.done ? AppColors.green : Colors.transparent,
                border: e.done ? null : Border.all(width: 2, color: e.current ? cc : pal.text.withValues(alpha: 0.14))),
              child: e.done && !compact ? Icon(Symbols.check, size: 9, weight: 700, color: pal.bg) : null),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent
                : e.done ? AppColors.green.withValues(alpha: 0.45) : pal.text.withValues(alpha: 0.08))),
          ])),
          const SizedBox(width: 11),
          Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: compact ? 7 : 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.name, style: AppTheme.bodySm.copyWith(
                    fontSize: compact ? 11.5 : 12,
                    color: e.current ? cc : e.done ? (compact ? pal.textMute : pal.text) : pal.textDim))),
                if (e.date != null) Text(e.date!, style: procMono(context, size: 10)),
              ]),
              if (e.note != null && e.note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(e.note!, style: AppTheme.bodySub.copyWith(fontSize: 10.5,
                    color: e.current ? pal.textMute : pal.textDim))),
            ]),
          )),
        ]));
      }),
    ]);
  }
}

/// Small segmented filter (All · 8 | Import · 7 …).
class ProcSegmented extends StatelessWidget {
  const ProcSegmented({super.key, required this.options, required this.selected, required this.onChanged});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    // Scrolls sideways when the options don't fit (phone widths).
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: pal.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < options.length; i++) GestureDetector(
          onTap: () => onChanged(i),
          child: Container(
            height: 24, padding: const EdgeInsets.symmetric(horizontal: 11), alignment: Alignment.center,
            decoration: BoxDecoration(color: i == selected ? pal.surface3 : null, borderRadius: BorderRadius.circular(7)),
            child: Text(options[i], style: AppTheme.bodySub.copyWith(fontSize: 11,
                color: i == selected ? pal.text : pal.textMute)),
          ),
        ),
      ]),
    ));
  }
}

class ProcFilterChip extends StatelessWidget {
  const ProcFilterChip(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 28, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: context.pal.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textMute)),
        const SizedBox(width: 6),
        Icon(Symbols.expand_more, size: 13, color: context.pal.textDim),
      ]),
    ),
  );
}

/// List search box — the Settings field look (FieldFocusBox: recessed box,
/// teal outline + halo while focused) with a leading search icon.
class ProcSearchField extends StatelessWidget {
  const ProcSearchField({super.key, required this.hint, this.onChanged, this.width = 260});
  final String hint;
  final ValueChanged<String>? onChanged;
  final double width;
  @override
  Widget build(BuildContext context) => SearchField(hint: hint, onChanged: onChanged, width: width);
}

/// Key/value grid used in permit, entity and shipment info panels.
class KvGrid extends StatelessWidget {
  const KvGrid(this.rows, {super.key, this.labelWidth = 96});
  final List<(String, Widget)> rows;
  final double labelWidth;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    child: Column(children: [
      for (final (k, v) in rows) Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: labelWidth, child: Text(k, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim))),
          Expanded(child: v),
        ]),
      ),
    ]),
  );
}

/// Initials avatar + role/name row for notification recipients.
class RecipientRow extends StatelessWidget {
  const RecipientRow({super.key, required this.initials, required this.role, this.name, this.tag, this.tagTone = ProcTone.teal});
  final String initials, role;
  final String? name, tag;
  final ProcTone tagTone;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
      child: Row(children: [
        CircleAvatar(radius: 13, backgroundColor: pal.surface3,
            child: Text(initials, style: procMono(context, size: 9.5, color: pal.textMute))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(role, style: AppTheme.bodySm.copyWith(fontSize: 12)),
          if (name != null) Text(name!, style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
        ])),
        if (tag != null) ProcTag(tag!, tone: tagTone, small: true),
      ]),
    );
  }
}

/// Audit entries (what / who · when).
class AuditList extends StatelessWidget {
  const AuditList(this.items, {super.key});
  final List<(String what, String who, String at, bool alert)> items;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (what, who, at, alert) in items) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(what, style: AppTheme.bodySm.copyWith(fontSize: 11.5, color: alert ? AppColors.coral : context.pal.text)),
          const SizedBox(height: 2),
          Text(at.isEmpty ? who : '$who · $at', style: AppTheme.bodySub.copyWith(fontSize: 10, color: context.pal.textDim)),
        ]),
      ),
    ]),
  );
}

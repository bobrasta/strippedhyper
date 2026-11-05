// NeST tender tracker building blocks: the tender row (table row on wide
// screens, card on phones), filter chips and the tag / pipeline pills.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/nest_tender.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'proc_widgets.dart';

ProcTone nestTagTone(String tag) => switch (tag) {
  'DEVICES' => ProcTone.teal,
  'REAGENTS' => ProcTone.violet,
  'CONSUMABLES' => ProcTone.green,
  'SERVICE' => ProcTone.amber,
  _ => ProcTone.neutral,
};

ProcTone nestPipelineTone(String p) => switch (p) {
  'reviewing' => ProcTone.teal,
  'bidding' => ProcTone.amber,
  'submitted' => ProcTone.violet,
  'won' => ProcTone.green,
  'lost' => ProcTone.coral,
  _ => ProcTone.neutral,
};

/// Closing date + countdown colour: red within 3 days, dim once closed.
Color nestClosingColor(BuildContext c, NestTender t) => !t.isOpen
    ? c.pal.textDim
    : t.isClosingSoon ? AppColors.coral : (t.closingInDays ?? 99) <= 7 ? AppColors.amber : c.pal.textMute;

String nestClosingText(NestTender t) {
  final at = t.closingAt;
  if (at == null) return 'No closing date';
  final eat = toEat(at);
  return '${formatDate(eat)} ${formatTime(eat)}';
}

/// On/off filter chip in the segmented-control look.
class NestToggleChip extends StatelessWidget {
  const NestToggleChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.tone});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final ProcTone? tone;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fg = selected ? (tone?.fg(context) ?? pal.text) : pal.textMute;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? (tone?.bg(context) ?? pal.surface3) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? fg.withValues(alpha: 0.6) : pal.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: fg, fill: selected ? 1 : 0), const SizedBox(width: 5)],
            Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: fg)),
          ]),
        ),
      ),
    );
  }
}

class NestTagPills extends StatelessWidget {
  const NestTagPills(this.tags, {super.key});
  final List<String> tags;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4, children: [
    for (final t in tags) ProcTag(nestTagLabel(t), tone: nestTagTone(t), small: true),
  ]);
}

/// One tender in a list. [wide] lays it out as a table row.
class NestTenderRow extends StatelessWidget {
  const NestTenderRow({super.key, required this.tender, required this.onTap, this.wide = false});
  final NestTender tender;
  final VoidCallback onTap;
  final bool wide;

  static const _gap = SizedBox(width: 14);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = tender;
    final closeColor = nestClosingColor(context, t);

    final status = ProcTag(nestPipelineLabel(t.pipelineStatus), tone: nestPipelineTone(t.pipelineStatus), small: true);
    final badges = [
      if (t.hasAddendum) const ProcTag('Addendum', tone: ProcTone.amber, small: true),
      if (t.relevance == 'maybe') const ProcTag('Maybe', small: true),
    ];
    final meta = [
      t.reference,
      if (t.lotCount != null) '${t.lotCount} lot${t.lotCount == 1 ? '' : 's'}',
      if (t.entityType != null && t.entityType != 'TENDER') t.entityType == 'FRAMEWORK' ? 'Framework' : 'Planned',
    ].join(' · ');

    final closing = Column(crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Text(nestClosingText(t), style: procMono(context, size: 11, color: closeColor), overflow: TextOverflow.ellipsis),
      Text(t.countdown, key: const ValueKey('countdown'), style: AppTheme.bodySub.copyWith(fontSize: 11,
          color: closeColor, fontWeight: t.isClosingSoon ? FontWeight.w600 : null)),
    ]);

    if (!wide) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: t.isClosingSoon ? AppColors.coral.withValues(alpha: 0.04) : null,
            border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.description, style: AppTheme.bodySm, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(t.procuringEntityName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
            const SizedBox(height: 2),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: procMono(context, size: 10.5)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: [
                status, ...badges,
                for (final tag in t.tags) ProcTag(nestTagLabel(tag), tone: nestTagTone(tag), small: true),
              ])),
              const SizedBox(width: 10),
              Flexible(child: closing),
            ]),
          ]),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      hoverColor: pal.surface2.withValues(alpha: 0.5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: t.isClosingSoon ? AppColors.coral.withValues(alpha: 0.04) : null,
          border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
        child: Row(children: [
          Expanded(flex: 30, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.description, style: AppTheme.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: procMono(context, size: 10.5)),
          ])),
          _gap,
          Expanded(flex: 16, child: Text(t.procuringEntityName ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
          _gap,
          Expanded(flex: 12, child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final tag in t.tags) ProcTag(nestTagLabel(tag), tone: nestTagTone(tag), small: true), ...badges,
          ])),
          _gap,
          SizedBox(width: 92, child: Align(alignment: Alignment.centerLeft, child: status)),
          _gap,
          SizedBox(width: 136, child: closing),
        ]),
      ),
    );
  }
}

/// Header for the wide table.
class NestTableHeader extends StatelessWidget {
  const NestTableHeader({super.key});
  @override
  Widget build(BuildContext context) {
    Widget h(String s, {int flex = 0, double? w, TextAlign a = TextAlign.left}) {
      final x = Text(s.toUpperCase(), style: procCaps(context), textAlign: a);
      return w != null ? SizedBox(width: w, child: x) : Expanded(flex: flex, child: x);
    }
    const gap = SizedBox(width: 14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
      child: Row(children: [
        h('Tender', flex: 30), gap, h('Procuring entity', flex: 16), gap, h('Tags', flex: 12), gap,
        h('Status', w: 92), gap, h('Closes', w: 136, a: TextAlign.right),
      ]),
    );
  }
}

/// Bordered empty-state box used by the NeST tabs.
class NestEmpty extends StatelessWidget {
  const NestEmpty(this.text, {super.key, this.icon = Symbols.travel_explore});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
      child: Column(children: [
        Icon(icon, size: 22, color: pal.textDim),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: AppTheme.bodySub.copyWith(color: pal.textDim)),
      ]),
    );
  }
}

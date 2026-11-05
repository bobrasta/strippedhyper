import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

/// Shared report-building blocks — icon+big-number tiles, a titled card
/// shell, a segmented stage bar, and a dotted "ticket-stub" label…value
/// row (the reference dashboards' static-info-panel look). Extracted so
/// every report screen (HR Dashboard, HR Reports, …) shares one visual
/// language instead of each hand-rolling its own KPI/list styling.

class ReportKpiTile extends StatelessWidget {
  const ReportKpiTile({super.key, required this.icon, required this.label, required this.value, this.accent});
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: accent ?? AppColors.teal),
      const SizedBox(height: 10),
      Text(value, style: AppTheme.kpiValue.copyWith(color: accent ?? context.pal.text, fontSize: 24)),
      const SizedBox(height: 2),
      Text(label, style: AppTheme.bodySub, maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.title, required this.icon, required this.child, this.trailing, this.accent});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  /// Each report section gets its own identity color (Staff=teal,
  /// Leave=violet, Recruitment=amber, …) instead of one flat neutral icon
  /// — defaults to the brand accent if a section doesn't set one.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppTheme.cardTitle)),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

/// Small colored count tile — used for breakdown entries (one department,
/// one gender, …) so a report reads as a grid of numbers, not a text list.
class ReportMiniStat extends StatelessWidget {
  const ReportMiniStat({super.key, required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('$value', style: AppTheme.bodyStrong.copyWith(fontSize: 17, color: color, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(label, style: AppTheme.monoXs, maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

/// A sub-heading inside a [ReportCard] for a named sub-table/list.
class ReportSubheading extends StatelessWidget {
  const ReportSubheading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10)),
  );
}

/// One block per category, filling the row — the reference dashboards'
/// "match rate" bar pattern, applied to any set of named counts.
class ReportStageBar extends StatelessWidget {
  const ReportStageBar({super.key, required this.byStage});
  final Map<String, int> byStage;

  static List<Color> _palette() => [AppColors.info, AppColors.teal, AppColors.amber, AppColors.violet, AppColors.coral];

  @override
  Widget build(BuildContext context) {
    final entries = byStage.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(4), child: Container(width: double.infinity, height: 7, color: context.pal.surface3));
    }
    final palette = _palette();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(flex: entries[i].value, child: Container(width: double.infinity, height: 7, color: palette[i % palette.length])),
      ]),
    );
  }
}

/// A dotted "ticket-stub" label … value row — static-info-panel look from
/// the reference dashboards.
class ReportTicketRow extends StatelessWidget {
  const ReportTicketRow({super.key, required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(label, style: AppTheme.bodySm.copyWith(color: context.pal.textMute)),
      const SizedBox(width: 6),
      Expanded(child: LayoutBuilder(builder: (ctx, cst) {
        final dotWidth = 4.0;
        final gap = 3.0;
        final count = math.max(0, (cst.maxWidth / (dotWidth + gap)).floor());
        return SizedBox(
          height: 10,
          child: Row(children: List.generate(count, (_) => Padding(
            padding: EdgeInsets.only(right: gap),
            child: Container(width: dotWidth, height: 1.5, color: context.pal.border),
          ))),
        );
      })),
      const SizedBox(width: 6),
      Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 12.5, color: valueColor)),
    ]),
  );
}

class ReportChip extends StatelessWidget {
  const ReportChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (color ?? AppColors.teal).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: AppTheme.monoXs.copyWith(color: color ?? AppColors.teal, fontSize: 11)),
  );
}

class ReportNotAvailableNote extends StatelessWidget {
  const ReportNotAvailableNote({super.key, required this.label, required this.reason});
  final String label, reason;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Symbols.info, size: 14, color: context.pal.textDim),
    const SizedBox(width: 8),
    Expanded(child: RichText(text: TextSpan(children: [
      TextSpan(text: '$label — ', style: AppTheme.bodySm.copyWith(fontSize: 12, color: context.pal.textMute)),
      TextSpan(text: reason, style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ]))),
  ]);
}

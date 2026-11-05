import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../charts/sparkline_chart.dart';

import '../../theme/app_palette.dart';
enum KpiAccent { teal, amber, coral }

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.unit,
    this.deltaValue,
    this.deltaUp,
    this.deltaNote,
    this.sparkValues,
    this.accent = KpiAccent.teal,
  });

  final String label;
  final IconData icon;
  final String value;
  final String? unit;
  // All four are optional — a caller with no real trend/history data (e.g.
  // a plain headcount or stock-value tile) omits them entirely rather than
  // faking a delta/sparkline; the delta pill and sparkline just don't render.
  final String? deltaValue;
  final bool? deltaUp;
  final String? deltaNote;
  final List<double>? sparkValues;
  final KpiAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (accent) {
      KpiAccent.teal  => AppColors.teal,
      KpiAccent.amber => AppColors.amber,
      KpiAccent.coral => AppColors.coral,
    };
    final hasDelta = deltaValue != null && deltaNote != null;
    final pillBg = (deltaUp ?? true) ? AppColors.tealSoft : AppColors.coralSoft;
    final pillFg = (deltaUp ?? true) ? AppColors.teal     : AppColors.coral;

    return LayoutBuilder(builder: (context, constraints) {
      // Compact mode: 2-column grid on phone (~159 px per card)
      final narrow = constraints.maxWidth < 180;
      final pad       = narrow ? 12.0 : 18.0;
      final sparkW    = narrow ? 56.0 : 96.0;
      final sparkH    = narrow ? 22.0 : 32.0;
      final valueSz   = narrow ? 22.0 : 30.0;
      final labelSz   = narrow ? 9.0  : 10.5;

      return Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label row
                Row(children: [
                  Icon(icon, size: narrow ? 12 : 14, color: context.pal.textDim),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: AppTheme.labelCaps.copyWith(fontSize: labelSz),
                      maxLines: narrow ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                SizedBox(height: narrow ? 8 : 12),

                // Value (hide unit on narrow to save space)
                narrow
                    ? Text(
                        value,
                        style: GoogleFonts.inter(
                          fontSize: valueSz,
                          fontWeight: FontWeight.w700,
                          color: context.pal.text,
                          letterSpacing: -0.02,
                          height: 1,
                          fontFeatures: [const FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : RichText(
                        text: TextSpan(
                          text: value,
                          style: AppTheme.kpiValue,
                          children: unit != null
                              ? [TextSpan(
                                  text: ' $unit',
                                  style: GoogleFonts.inter(
                                    fontSize: 14, fontWeight: FontWeight.w500,
                                    color: context.pal.textMute,
                                  ),
                                )]
                              : null,
                        ),
                      ),

                if (hasDelta) ...[
                  SizedBox(height: narrow ? 6 : 10),

                  // Delta row — hide note text on narrow
                  // The note shrinks (ellipsis) so a long note can't
                  // overflow a narrow card; the pill keeps its size.
                  Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: narrow ? 5 : 7,
                        vertical: narrow ? 1 : 2,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          (deltaUp ?? true) ? Icons.arrow_upward : Icons.arrow_downward,
                          size: narrow ? 10 : 11,
                          color: pillFg,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          deltaValue!,
                          style: AppTheme.bodySub.copyWith(
                            color: pillFg,
                            fontSize: narrow ? 10 : 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ]),
                    ),
                    if (!narrow) ...[
                      const SizedBox(width: 6),
                      Expanded(child: Text(deltaNote!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySub.copyWith(fontSize: 12))),
                    ],
                  ]),
                ],
              ],
            ),

            // Sparkline — bottom-right corner
            if (sparkValues != null)
              Positioned(
                right: 0, bottom: 0,
                child: Opacity(
                  opacity: 0.7,
                  child: SparklineChart(
                    values: sparkValues!,
                    color: accentColor,
                    width: sparkW,
                    height: sparkH,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

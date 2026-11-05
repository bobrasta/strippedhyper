import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

import '../../theme/app_palette.dart';

class RevenueLineChart extends StatelessWidget {
  const RevenueLineChart({
    super.key,
    this.actual  = const [],
    this.target  = const [],
    this.months  = const [],
    this.latestValue,
    this.latestLabel,
    this.aboveTarget,
  });

  final List<double> actual;
  final List<double> target;
  final List<String> months;
  final String? latestValue;
  final String? latestLabel;
  final String? aboveTarget;

  @override
  Widget build(BuildContext context) {
    if (actual.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text('No revenue data', style: TextStyle(color: context.pal.textDim)),
        ),
      );
    }

    FlSpot spot(int i, List<double> d) => FlSpot(i.toDouble(), d[i]);
    final actualSpots = List.generate(actual.length, (i) => spot(i, actual));
    final targetSpots = List.generate(target.length, (i) => spot(i, target));

    final maxY = [...actual, ...target].fold(0.0, (a, b) => b > a ? b : a);
    final minY = [...actual, ...target].fold(double.infinity, (a, b) => b < a ? b : a);
    final yPad = (maxY - minY) * 0.15;
    final chartMinY = (minY - yPad).clamp(0.0, double.infinity);
    final chartMaxY = maxY + yPad;

    final latestActual = actual.isNotEmpty ? actual.last : 0.0;
    final latestTargetVal = target.isNotEmpty ? target.last : 0.0;
    final diff = latestActual - latestTargetVal;
    final diffStr = diff >= 0
        ? '+${(diff / 1000000).toStringAsFixed(1)}M above target'
        : '${(diff / 1000000).toStringAsFixed(1)}M below target';
    final valueStr = latestValue ?? 'TSh ${(latestActual / 1000000).toStringAsFixed(1)}M';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(valueStr,
                style: AppTheme.kpiValue.copyWith(fontSize: 26, letterSpacing: -0.02)),
              Text.rich(TextSpan(
                text: '${months.isNotEmpty ? months.last : ''} · ',
                style: AppTheme.bodySub,
                children: [
                  TextSpan(
                    text: aboveTarget ?? diffStr,
                    style: AppTheme.bodySub.copyWith(
                      color: diff >= 0 ? AppColors.teal : AppColors.coral,
                    ),
                  ),
                ],
              )),
            ]),
            const Spacer(),
            Row(children: [
              _Legend(color: AppColors.teal, label: 'Actual'),
              const SizedBox(width: 14),
              _Legend(color: context.pal.textDim, label: 'Target', dashed: true),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: 0, maxX: (actual.length - 1).toDouble(),
              minY: chartMinY, maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (chartMaxY - chartMinY) / 4,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0x0DFFFFFF), strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: (chartMaxY - chartMinY) / 4,
                    reservedSize: 36,
                    getTitlesWidget: (v, _) => Text(
                      '${(v / 1000000).toStringAsFixed(0)}M',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 9, color: context.pal.textDim),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= months.length) return const SizedBox.shrink();
                      return Text(months[i],
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5, color: context.pal.textDim));
                    },
                  ),
                ),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: targetSpots,
                  color: context.pal.textDim.withValues(alpha: 0.7),
                  barWidth: 1.2,
                  dashArray: [4, 4],
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
                LineChartBarData(
                  spots: actualSpots,
                  color: AppColors.teal,
                  barWidth: 2,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                      radius: idx == actualSpots.length - 1 ? 4 : 2.5,
                      color: AppColors.teal,
                      strokeColor: context.pal.bg,
                      strokeWidth: idx == actualSpots.length - 1 ? 2 : 1,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [
                        AppColors.teal.withValues(alpha: 0.25),
                        AppColors.teal.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => context.pal.surface2,
                  getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                    'TSh ${(s.y / 1000000).toStringAsFixed(1)}M',
                    GoogleFonts.jetBrainsMono(
                        fontSize: 10.5, color: context.pal.text),
                  )).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: dashed ? null : color,
        borderRadius: BorderRadius.circular(2),
        border: dashed ? Border(top: BorderSide(color: color, width: 1)) : null,
      ),
    ),
    const SizedBox(width: 6),
    Text(label, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
  ]);
}

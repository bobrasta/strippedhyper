import 'package:flutter/material.dart';
import '../../utils/format.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'labeled_field.dart';

/// Reporting period used by every dated list and dashboard. The app shows
/// "This year" everywhere unless the user picks something else.
enum PeriodPreset { today, thisWeek, thisYear, thisQuarter, thisMonth, lastYear, allTime, custom }

class Period {
  const Period._(this.preset, this.from, this.to);

  final PeriodPreset preset;
  final DateTime? from; // inclusive, date-only
  final DateTime? to;   // inclusive, date-only

  static Period get defaultPeriod => Period.of(PeriodPreset.thisYear);

  factory Period.of(PeriodPreset p, {DateTime? now}) {
    final n = now ?? DateTime.now();
    switch (p) {
      case PeriodPreset.today:
        return Period._(p, DateTime(n.year, n.month, n.day), DateTime(n.year, n.month, n.day));
      case PeriodPreset.thisWeek:
        // Monday to Sunday.
        final mon = DateTime(n.year, n.month, n.day - (n.weekday - 1));
        return Period._(p, mon, DateTime(mon.year, mon.month, mon.day + 6));
      case PeriodPreset.thisYear:
        return Period._(p, DateTime(n.year, 1, 1), DateTime(n.year, 12, 31));
      case PeriodPreset.thisQuarter:
        final q0 = ((n.month - 1) ~/ 3) * 3 + 1;
        return Period._(p, DateTime(n.year, q0, 1), DateTime(n.year, q0 + 3, 0));
      case PeriodPreset.thisMonth:
        return Period._(p, DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 0));
      case PeriodPreset.lastYear:
        return Period._(p, DateTime(n.year - 1, 1, 1), DateTime(n.year - 1, 12, 31));
      case PeriodPreset.allTime:
      case PeriodPreset.custom:
        return Period._(PeriodPreset.allTime, null, null);
    }
  }

  factory Period.custom(DateTime from, DateTime to) =>
      Period._(PeriodPreset.custom, DateTime(from.year, from.month, from.day), DateTime(to.year, to.month, to.day));

  bool get isDefault => preset == PeriodPreset.thisYear;
  bool get isAllTime => preset == PeriodPreset.allTime;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? get fromIso => from == null ? null : _iso(from!);
  String? get toIso => to == null ? null : _iso(to!);

  /// Query parameters for the API's FiltersByPeriod (plus a page size big
  /// enough to hold a whole period, so lists aren't cut at page 1).
  Map<String, dynamic> get query => {
        'date_from': ?fromIso,
        'date_to': ?toIso,
        'per_page': 2000,
      };

  /// The single calendar year this period sits in, if it does.
  int? get year => from != null && to != null && from!.year == to!.year ? from!.year : null;

  bool contains(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (from != null && day.isBefore(from!)) return false;
    if (to != null && day.isAfter(to!)) return false;
    return true;
  }

  String get label => switch (preset) {
        PeriodPreset.today => 'Today',
        PeriodPreset.thisWeek => 'This week',
        PeriodPreset.thisYear => 'This year',
        PeriodPreset.thisQuarter => 'This quarter',
        PeriodPreset.thisMonth => 'This month',
        PeriodPreset.lastYear => 'Last year',
        PeriodPreset.allTime => 'All time',
        PeriodPreset.custom => '${formatDate(from!)} – ${formatDate(to!)}',
      };

  @override
  bool operator ==(Object other) => other is Period && other.preset == preset && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

/// Period picker in the shared Settings field box. "Custom range…" opens a
/// date-range picker; the chosen range then shows as the current value.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged, this.width = 190});

  final Period value;
  final ValueChanged<Period> onChanged;
  final double? width;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: value.from != null && value.to != null ? DateTimeRange(start: value.from!, end: value.to!) : null,
    );
    if (r != null) onChanged(Period.custom(r.start, r.end));
  }

  @override
  Widget build(BuildContext context) {
    const presets = [PeriodPreset.today, PeriodPreset.thisWeek, PeriodPreset.thisMonth, PeriodPreset.thisQuarter, PeriodPreset.thisYear, PeriodPreset.lastYear, PeriodPreset.allTime];
    return DropdownFieldBox<PeriodPreset>(
      width: width,
      value: value.preset,
      active: !value.isDefault,
      items: [
        for (final p in presets) DropdownMenuItem(value: p, child: Text(Period.of(p).label, overflow: TextOverflow.ellipsis)),
        DropdownMenuItem(
          value: PeriodPreset.custom,
          child: Text(value.preset == PeriodPreset.custom ? value.label : 'Custom range…', overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: (p) {
        if (p == null) return;
        if (p == PeriodPreset.custom) {
          _pickCustom(context);
        } else if (p != value.preset) {
          onChanged(Period.of(p));
        }
      },
    );
  }
}

/// "As at" date in the shared field box, for filter bars: null means today
/// (the live figures); a past date shows balances as they stood then. Teal
/// border while set, × to go back to today.
class AsAtDateBox extends StatelessWidget {
  const AsAtDateBox({super.key, required this.value, required this.onChanged, this.width = 190});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final double? width;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: value ?? now, firstDate: DateTime(2015), lastDate: now,
        helpText: 'Balances as at');
    if (d == null) return;
    final today = DateTime(now.year, now.month, now.day);
    onChanged(d.isBefore(today) ? d : null);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _pick(context),
    child: Container(
      width: width,
      height: fieldHeightOf(context),
      decoration: fieldBoxDecoration(context, active: value != null),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Expanded(child: Text(value == null ? 'As at today' : 'As at ${formatDate(value!)}', maxLines: 1,
            overflow: TextOverflow.ellipsis, style: AppTheme.fieldText.copyWith(color: context.pal.text))),
        if (value != null) ...[
          GestureDetector(onTap: () => onChanged(null), child: Icon(Symbols.close, size: 14, color: context.pal.textDim)),
          const SizedBox(width: 8),
        ],
        Icon(Symbols.calendar_month, size: 15, color: context.pal.textDim),
      ]),
    ),
  );
}

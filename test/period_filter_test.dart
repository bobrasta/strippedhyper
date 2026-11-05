import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/widgets/common/period_filter.dart';

void main() {
  // Thursday 1 Oct 2026.
  final now = DateTime(2026, 10, 1, 15, 30);

  test('Today covers just today', () {
    final p = Period.of(PeriodPreset.today, now: now);
    expect(p.fromIso, '2026-10-01');
    expect(p.toIso, '2026-10-01');
    expect(p.label, 'Today');
  });

  test('This week runs Monday to Sunday', () {
    final p = Period.of(PeriodPreset.thisWeek, now: now);
    expect(p.fromIso, '2026-09-28');
    expect(p.toIso, '2026-10-04');
    expect(Period.of(PeriodPreset.thisWeek, now: DateTime(2026, 9, 28)).fromIso, '2026-09-28');
    expect(Period.of(PeriodPreset.thisWeek, now: DateTime(2026, 10, 4)).fromIso, '2026-09-28');
  });
}

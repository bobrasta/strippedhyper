import 'package:flutter/material.dart';
import 'hr_reports_tab.dart';

/// Own top-level destination — HrReportsTab now renders its own full page
/// header (accent bar/title/actions), matching the HR Redesign spec, so
/// this wrapper is just a pass-through.
class HrReportsScreen extends StatelessWidget {
  const HrReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const HrReportsTab();
}

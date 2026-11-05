import 'package:flutter/material.dart';
import 'hr_recruitment_tab.dart';

/// Own top-level destination — HrRecruitmentTab now renders its own full
/// page header (accent bar/title/actions), matching the HR Redesign spec,
/// so this wrapper is just a pass-through.
class HrRecruitmentScreen extends StatelessWidget {
  const HrRecruitmentScreen({super.key});

  @override
  Widget build(BuildContext context) => const HrRecruitmentTab();
}

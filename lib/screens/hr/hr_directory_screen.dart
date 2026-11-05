import 'package:flutter/material.dart';
import 'hr_directory_tab.dart';

/// Own top-level destination — HrDirectoryTab now renders its own full
/// page header (accent bar/title/stats), matching the HR Redesign spec,
/// so this wrapper is just a pass-through.
class HrDirectoryScreen extends StatelessWidget {
  const HrDirectoryScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  Widget build(BuildContext context) => HrDirectoryTab(onNavigateTo: onNavigateTo);
}

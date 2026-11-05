import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'app_colors.dart';

/// Category colors for HR (and, once proven out, other modules) — a thin
/// mapping layer on top of the EXISTING AppColors tokens. Values match the
/// HR Redesign spec's own color legend exactly (people/leave/contracts/
/// payroll/recruitment/discipline) — every hue there except "people" was
/// already an exact match for an existing token (contracts=coral,
/// discipline=info, recruitment=violet, leave=amber, payroll=green);
/// "people" needed a new fixed cyan (AppColors.cyan) since the redesign
/// deliberately gives it an identity distinct from the brand accent
/// (payroll owns the brand green here, not people).
enum HrCategory { people, leave, contracts, payroll, recruitment, discipline }

extension HrCategoryColor on HrCategory {
  /// Full-strength color for icons, numbers, borders.
  Color get color => switch (this) {
    HrCategory.people => AppColors.cyan,
    HrCategory.leave => AppColors.amber,
    HrCategory.contracts => AppColors.coral,
    HrCategory.payroll => AppColors.green,
    HrCategory.recruitment => AppColors.violet,
    HrCategory.discipline => AppColors.info,
  };

  /// Low-alpha tint for card backgrounds and badge fills.
  Color get soft => switch (this) {
    HrCategory.people => AppColors.cyanSoft,
    HrCategory.leave => AppColors.amberSoft,
    HrCategory.contracts => AppColors.coralSoft,
    HrCategory.payroll => AppColors.greenSoft,
    HrCategory.recruitment => AppColors.violetSoft,
    HrCategory.discipline => AppColors.withAlpha(AppColors.info, 0.14),
  };

  // Symbols.* rather than the recommendation's Icons.* — this codebase
  // uses material_symbols_icons exclusively (no screen anywhere imports
  // the plain Icons class), so this substitutes the closest equivalent
  // rather than introducing a second icon set.
  IconData get icon => switch (this) {
    HrCategory.people => Symbols.groups,
    HrCategory.leave => Symbols.calendar_month,
    HrCategory.contracts => Symbols.description,
    HrCategory.payroll => Symbols.payments,
    HrCategory.recruitment => Symbols.person_search,
    HrCategory.discipline => Symbols.gavel,
  };

  String get label => switch (this) {
    HrCategory.people => 'People',
    HrCategory.leave => 'Leave',
    HrCategory.contracts => 'Contracts',
    HrCategory.payroll => 'Payroll',
    HrCategory.recruitment => 'Recruitment',
    HrCategory.discipline => 'Discipline',
  };
}

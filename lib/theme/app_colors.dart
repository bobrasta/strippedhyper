import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Hypermed design tokens — ported from the gwgps Fleet Command design
/// system (see gwgps-app/public/css/fleet-command.css + theme-overrides.css).
/// Dark-theme static defaults; adaptive per-theme values live in AppPalette.
class AppColors {
  AppColors._();

  // ── Dark surfaces ──────────────────────────────────────────
  static const Color bg          = Color(0xFF08090B); // canvas
  static const Color surface1    = Color(0xFF111418); // cards, panels (panel-solid)
  static const Color surface2    = Color(0xFF1B1F27); // inset / secondary
  static const Color surface3    = Color(0xFF20242D); // inputs, nested
  static const Color sidebarBg   = Color(0xFF08090B);
  static const Color topbarBg    = Color(0xFF08090B);

  // ── Dark borders ──────────────────────────────────────────
  static const Color border      = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const Color borderStrong= Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const Color divider     = Color(0x14FFFFFF);

  // ── Dark text ─────────────────────────────────────────────
  static const Color text        = Color(0xFFF3F5F7);
  static const Color textMute    = Color(0xFFA3ABB4); // gwgps --text-dim (1st tier)
  static const Color textDim     = Color(0xFF6A727B); // gwgps --text-mute (2nd tier)

  // ── Brand — accent (theme-reactive) ─────────────────────────
  // `teal`/`blue`/`green` are aliases of ONE brand-accent concept (kept
  // separately named for backward compat across existing call sites) — all
  // three now read the active theme's AppPalette.blue/statusWarning/
  // statusCritical live, via AppTheme.pal, instead of a fixed hardcoded
  // green. Previously these were `const`, which meant no theme (including a
  // future one) could ever actually change them — every button/badge across
  // the app rendered the same green regardless of selected theme. Getters
  // are not compile-time constants, so any `const` expression wrapping one
  // of these now needs that `const` removed (flutter analyze finds them all
  // — see the sweep after this change in project memory).
  static Color get teal        => AppTheme.pal.blue;
  static Color get tealSoft    => AppTheme.pal.blue.withValues(alpha: 0.14);
  static Color get tealGlow    => AppTheme.pal.blue.withValues(alpha: 0.35);

  static Color get blue        => AppTheme.pal.blue;
  static Color get blueSoft    => AppTheme.pal.blue.withValues(alpha: 0.14);
  // AppPalette.light/neutral's blue700 (0xFF16A34A) doesn't match this
  // fixed value's old dark-mode-tuned green (0xFF4ADE80) — pin it for every
  // pre-existing theme so this change is invisible there, and only let it
  // vary for themes added after this fix.
  static Color get blueStrong  => switch (themeNotifier.value) {
    AppThemeMode.dark || AppThemeMode.light || AppThemeMode.neutral => const Color(0xFF4ADE80),
    AppThemeMode.aurora ||
    AppThemeMode.hypermed ||
    AppThemeMode.hypermedLight ||
    AppThemeMode.slateDusk ||
    AppThemeMode.ledgerPaper ||
    AppThemeMode.carbonAmber ||
    AppThemeMode.nocturne ||
    AppThemeMode.daylight ||
    AppThemeMode.forestDeep ||
    AppThemeMode.inkCopper => AppTheme.pal.blue700,
  };

  static Color get green       => AppTheme.pal.green;
  static Color get greenSoft   => AppTheme.pal.green.withValues(alpha: 0.14);

  static Color get amber       => AppTheme.pal.statusWarning;
  static Color get amberSoft   => AppTheme.pal.statusWarning.withValues(alpha: 0.14);

  static Color get coral       => AppTheme.pal.statusCritical;
  static Color get coralSoft   => AppTheme.pal.statusCritical.withValues(alpha: 0.14);

  static const Color violet      = Color(0xFFA78BFA); // gwgps --violet — secondary accent, not part of the brand-accent leak this fixes
  static const Color violetSoft  = Color(0x29A78BFA);

  static const Color info        = Color(0xFF38BDF8); // gwgps --info

  // Fixed, theme-invariant cyan — the "People" HR category needs its own
  // identity distinct from the brand accent (payroll now owns the actual
  // brand green in the HR Redesign color legend). Same fixed-constant
  // pattern as violet above, not a AppTheme.pal-derived role.
  static const Color cyan        = Color(0xFF2DD4BF);
  static const Color cyanSoft    = Color(0x292DD4BF);

  // ── Radii (gwgps --r-sm/md/lg/xl) ───────────────────────────
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rLg = 18;
  static const double rXl = 24;

  // ── Gradient presets (getters — colors above are no longer const) ──
  static LinearGradient get avatarGradient => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [blue, violet],
  );
  static LinearGradient get avatarTealGradient => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [teal, const Color(0xFF2F7FC2)],
  );
  static LinearGradient get avatarAmberGradient => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [amber, const Color(0xFFB8900A)],
  );
  static LinearGradient get avatarCoralGradient => LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [coral, const Color(0xFFB83A38)],
  );
  static const LinearGradient avatarVioletGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [violet, Color(0xFF6B4EC8)],
  );

  static Color withAlpha(Color c, double opacity) =>
      c.withValues(alpha: opacity);
}

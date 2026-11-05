import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_palette.dart';

/// Theme mode. The first five are the originals; the nine after them are the
/// palettes added from the 2026-09-02 theme review.
///
/// [hypermed] / [hypermedLight] are built from the company logo (blue
/// 0xFF5088C8, green 0xFF30A850). There is deliberately no `midnight` —
/// [dark] already IS Midnight (bg 0xFF08090B, surface1 0xFF111418, accent
/// 0xFF22C55E).
enum AppThemeMode {
  light,
  dark,
  neutral,
  aurora,
  hypermed,
  hypermedLight,
  slateDusk,
  ledgerPaper,
  carbonAmber,
  nocturne,
  daylight,
  forestDeep,
  inkCopper,
}

/// Global theme-mode notifier — toggled by the top-bar button or Settings.
/// Lives here (not main.dart) so the static typography helpers below can
/// read the active palette without needing a BuildContext. Defaults to
/// [AppThemeMode.aurora] — the user asked for the warm-gradient look to be
/// the system's identity, not an opt-in extra alongside the older themes.
/// The nine palettes added 2026-09-02 are opt-in additions to the picker,
/// not a default change.
final themeNotifier = ValueNotifier<AppThemeMode>(AppThemeMode.aurora);

/// App-wide text-size preference, applied as a MediaQuery text-scale
/// multiplier in main.dart (on top of the device's own scale, so OS
/// accessibility settings still apply). 'medium' is the default — the same
/// bump the app shipped with before this became user-adjustable.
enum TextSizePref {
  small(1.0), medium(1.1), large(1.2);
  const TextSizePref(this.scale);
  final double scale;
}

/// Global text-size notifier — toggled from Settings → Preferences.
/// Same "lives in memory only, not persisted across restarts" behavior as
/// [themeNotifier] above — consistent, not accidental.
final textSizeNotifier = ValueNotifier<TextSizePref>(TextSizePref.medium);

class AppTheme {
  AppTheme._();

  /// The palette matching the current [themeNotifier] value — lets static
  /// TextStyle getters below stay theme-correct without a BuildContext.
  static AppPalette get pal => switch (themeNotifier.value) {
    AppThemeMode.dark          => AppPalette.dark,
    AppThemeMode.light         => AppPalette.light,
    AppThemeMode.neutral       => AppPalette.neutral,
    AppThemeMode.aurora        => AppPalette.aurora,
    AppThemeMode.hypermed      => AppPalette.hypermed,
    AppThemeMode.hypermedLight => AppPalette.hypermedLight,
    AppThemeMode.slateDusk     => AppPalette.slateDusk,
    AppThemeMode.ledgerPaper   => AppPalette.ledgerPaper,
    AppThemeMode.carbonAmber   => AppPalette.carbonAmber,
    AppThemeMode.nocturne      => AppPalette.nocturne,
    AppThemeMode.daylight      => AppPalette.daylight,
    AppThemeMode.forestDeep    => AppPalette.forestDeep,
    AppThemeMode.inkCopper     => AppPalette.inkCopper,
  };

  // ── Dark theme ─────────────────────────────────────────────────────────────

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  // ── Light theme ────────────────────────────────────────────────────────────

  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  // ── Neutral theme ──────────────────────────────────────────────────────────

  static ThemeData neutral() => _build(AppPalette.neutral, Brightness.light);

  // ── Aurora theme ───────────────────────────────────────────────────────────

  static ThemeData aurora() => _build(AppPalette.aurora, Brightness.light);

  // ── Brand themes ───────────────────────────────────────────────────────────

  static ThemeData hypermed() => _build(AppPalette.hypermed, Brightness.dark);

  static ThemeData hypermedLight() =>
      _build(AppPalette.hypermedLight, Brightness.light);

  // ── Added palettes (2026-09-02 theme review) ────────────────────────────────

  static ThemeData slateDusk() => _build(AppPalette.slateDusk, Brightness.dark);

  static ThemeData ledgerPaper() =>
      _build(AppPalette.ledgerPaper, Brightness.light);

  static ThemeData carbonAmber() =>
      _build(AppPalette.carbonAmber, Brightness.dark);

  static ThemeData nocturne() => _build(AppPalette.nocturne, Brightness.dark);

  static ThemeData daylight() => _build(AppPalette.daylight, Brightness.light);

  static ThemeData forestDeep() =>
      _build(AppPalette.forestDeep, Brightness.dark);

  static ThemeData inkCopper() => _build(AppPalette.inkCopper, Brightness.dark);

  /// Convenience for the theme switcher: resolve a mode straight to its
  /// ThemeData without a fourteen-arm switch at every call site.
  static ThemeData of(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light         => light(),
    AppThemeMode.dark          => dark(),
    AppThemeMode.neutral       => neutral(),
    AppThemeMode.aurora        => aurora(),
    AppThemeMode.hypermed      => hypermed(),
    AppThemeMode.hypermedLight => hypermedLight(),
    AppThemeMode.slateDusk     => slateDusk(),
    AppThemeMode.ledgerPaper   => ledgerPaper(),
    AppThemeMode.carbonAmber   => carbonAmber(),
    AppThemeMode.nocturne      => nocturne(),
    AppThemeMode.daylight      => daylight(),
    AppThemeMode.forestDeep    => forestDeep(),
    AppThemeMode.inkCopper     => inkCopper(),
  };

  /// Human labels for the Settings picker, in presentation order — the
  /// original five first (aurora, today's default, leads), then the added
  /// brand/dark/light palettes.
  static const List<(AppThemeMode, String)> pickerOrder = [
    (AppThemeMode.aurora,        'Aurora'),
    (AppThemeMode.dark,          'Midnight'),
    (AppThemeMode.light,         'Light'),
    (AppThemeMode.neutral,       'Neutral'),
    (AppThemeMode.hypermed,      'Hypermed'),
    (AppThemeMode.hypermedLight, 'Hypermed Light'),
    (AppThemeMode.slateDusk,     'Slate Dusk'),
    (AppThemeMode.nocturne,      'Nocturne'),
    (AppThemeMode.carbonAmber,   'Carbon Amber'),
    (AppThemeMode.forestDeep,    'Forest Deep'),
    (AppThemeMode.inkCopper,     'Ink & Copper'),
    (AppThemeMode.ledgerPaper,   'Ledger Paper'),
    (AppThemeMode.daylight,      'Daylight'),
  ];

  // ── Shared builder ─────────────────────────────────────────────────────────

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    final textTheme = base.textTheme.apply(
      fontFamily: 'TildaSans',
      bodyColor: p.text,
      displayColor: p.text,
    ).copyWith(
      bodyMedium: TextStyle(fontFamily: 'TildaSans', color: p.text,     fontSize: 13),
      bodySmall:  TextStyle(fontFamily: 'TildaSans', color: p.textMute, fontSize: 11.5),
    );

    // Every pre-existing theme keeps its exact original onPrimary (dark
    // near-black on isDark, white otherwise) — do not derive this from
    // p.blue's luminance app-wide, since that would also silently repaint
    // light/neutral (whose green primary already reads as "light" under
    // Flutter's own brightness estimate, same as aurora's gold does) and
    // break the "pre-existing themes render byte-identical" rule from the
    // earlier theme ports. Aurora's gold genuinely needs dark text — white
    // barely contrasts on it — so it gets its own branch instead.
    //
    // Two of the 2026-09-02 palettes invert that rule and so need naming
    // BEFORE the isDark guard (arms are matched in order): hypermed's brand
    // blue 0xFF5088C8 is mid-dark (white ink reads, dark near-black does
    // not), and nocturne's blurple 0xFF9184D9 is a light accent on a dark
    // ground so it takes the ground colour as its ink, per that system.
    final onPrimary = switch (themeNotifier.value) {
      AppThemeMode.hypermed   => const Color(0xFFF7FAFD),
      AppThemeMode.nocturne   => const Color(0xFF161826),
      _ when p.isDark         => const Color(0xFF0A1119),
      AppThemeMode.aurora     => const Color(0xFF1C1712),
      _                       => Colors.white,
    };

    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      colorScheme: brightness == Brightness.dark
          ? ColorScheme.dark(
              surface:     p.bg,
              primary:     p.blue,
              secondary:   p.statusWarning,
              error:       p.statusCritical,
              onPrimary:   onPrimary,
              onSecondary: p.bg,
              onSurface:   p.text,
            )
          : ColorScheme.light(
              surface:     p.bg,
              primary:     p.blue,
              secondary:   p.statusWarning,
              error:       p.statusCritical,
              onPrimary:   onPrimary,
              onSecondary: p.bg,
              onSurface:   p.text,
            ),
      textTheme: textTheme,
      dividerColor: p.divider,
      cardTheme: CardThemeData(
        color: p.surface1,
        elevation: p.isDark ? 0 : 1,
        shadowColor: p.isDark ? Colors.transparent : const Color(0x14000000),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppColors.rLg)),
          side: BorderSide(color: p.border),
        ),
        margin: EdgeInsets.zero,
      ),
      // Matches FieldFocusBox (recessed bg fill, borderStrong outline,
      // accent on focus) so stock TextField/TextFormFields look the same as
      // the boxed fields.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderStrong, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderStrong, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.blue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.statusCritical, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.statusCritical, width: 1.6),
        ),
        labelStyle: TextStyle(fontFamily: 'TildaSans', fontSize: 13, color: p.textMute),
        hintStyle: TextStyle(fontFamily: 'TildaSans', fontSize: 14, color: p.textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(p.border),
        radius: const Radius.circular(999),
      ),
      extensions: [p],
    );
  }

  // ── Typography helpers ─────────────────────────────────────────────────────
  // Colors below track the active theme via [pal] (resolved from the global
  // [themeNotifier], not BuildContext) — they stay correct in light/dark/
  // neutral without every call site needing its own .copyWith(color: ...).

  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 11.5, color: pal.textMute, letterSpacing: -0.01,
  );
  static TextStyle get monoXs => GoogleFonts.jetBrainsMono(
    fontSize: 10.5, color: pal.textDim, letterSpacing: 0.04,
  );
  static TextStyle get labelCaps => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 10.5, color: pal.textDim, fontWeight: FontWeight.w500,
    letterSpacing: 0.13, height: 1,
  );
  // These four used to omit color entirely, relying on Text widgets
  // inheriting the ambient themed DefaultTextStyle — which silently breaks
  // (falls back to Flutter's own default, near-black) anywhere that
  // inheritance doesn't reach: a separate Overlay route, a Positioned
  // overlay atop a map, a widget built outside the normal tree — exactly
  // the same class of bug bodySm below was already fixed for. Explicit
  // color: pal.text closes it here too, everywhere these are used.
  static TextStyle get kpiValue => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 30, fontWeight: FontWeight.w700,
    letterSpacing: -0.02, height: 1, color: pal.text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  static TextStyle get pageTitle => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.01, color: pal.text,
  );
  static TextStyle get cardTitle => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.005, color: pal.text,
  );
  static TextStyle get bodyStrong => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 13, fontWeight: FontWeight.w500, color: pal.text,
  );
  // Unlike the other named styles above (which lean on plain Text widgets
  // correctly inheriting DefaultTextStyle from the themed textTheme), this
  // one needed an explicit color: it's the style nearly every DropdownButton
  // in the app passes as `style:`, and a dropdown's open menu renders in a
  // separate Overlay route that doesn't reliably inherit the ambient
  // DefaultTextStyle — without a color here it fell back to Flutter's own
  // default rather than the active palette, which read fine by luck on dark
  // themes and was invisible (light text on a light menu) on light ones.
  static TextStyle get bodySm => TextStyle(fontFamily: 'TildaSans', fontSize: 12.5, color: pal.text);

  // Text-entry fields — one definition for every field in the app (the
  // look the Settings profile form set: sentence-case label above, 14px
  // input). See FieldFocusBox / LabeledTextField / SearchField.
  static TextStyle get fieldLabel => TextStyle(fontFamily: 'TildaSans', fontSize: 13, fontWeight: FontWeight.w400, color: pal.textMute);
  static TextStyle get fieldText => TextStyle(fontFamily: 'TildaSans', fontSize: 14, fontWeight: FontWeight.w400, color: pal.text);
  static TextStyle get fieldHint => TextStyle(fontFamily: 'TildaSans', fontSize: 14, fontWeight: FontWeight.w400, color: pal.textDim);
  static TextStyle get bodySub => TextStyle(
    fontFamily: 'TildaSans',
    fontSize: 11.5, color: pal.textMute,
  );
}

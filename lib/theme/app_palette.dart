import 'package:flutter/material.dart';

/// Adaptive colour tokens — all values that vary across light / dark / neutral.
/// Brand / accent colours that do NOT vary (e.g. violet for avatars) stay in AppColors.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.sidebarBg,
    required this.topbarBg,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.text,
    required this.textMute,
    required this.textDim,
    required this.blue,
    required this.blue700,
    required this.blue50,
    required this.green,
    required this.green50,
    required this.statusNormal,
    required this.statusInfo,
    required this.statusWarning,
    required this.statusCritical,
    required this.isDark,
    this.bgGradient,
  });

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color sidebarBg;
  final Color topbarBg;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color text;
  final Color textMute;
  final Color textDim;

  // Brand blues (primary actions, links, focus)
  final Color blue;
  final Color blue700;   // hover / pressed
  final Color blue50;    // selected rows, info tints

  // Brand greens (success, confirmations)
  final Color green;
  final Color green50;

  // Semantic status
  final Color statusNormal;
  final Color statusInfo;
  final Color statusWarning;
  final Color statusCritical;

  final bool isDark;

  // Optional diagonal wash painted behind the app shell instead of a flat
  // [bg] — null for every existing theme (unchanged flat-color behavior);
  // only a theme that explicitly wants the soft gradient-canvas look (see
  // [aurora]) sets this. [bg] still gates Scaffold.backgroundColor as a
  // solid fallback either way.
  final List<Color>? bgGradient;

  // ── Dark ─────────────────────────────────────────────────────────────────────

  static const dark = AppPalette(
    isDark:         true,
    bg:             Color(0xFF08090B),
    surface1:       Color(0xFF111418), // panel-solid
    surface2:       Color(0xFF1B1F27),
    surface3:       Color(0xFF20242D),
    sidebarBg:      Color(0xFF08090B),
    topbarBg:       Color(0xFF08090B),
    border:         Color(0x14FFFFFF), // rgba(255,255,255,.08)
    borderStrong:   Color(0x29FFFFFF), // rgba(255,255,255,.16)
    divider:        Color(0x14FFFFFF),
    text:           Color(0xFFF3F5F7),
    textMute:       Color(0xFFA3ABB4), // gwgps --text-dim (1st tier)
    textDim:        Color(0xFF6A727B), // gwgps --text-mute (2nd tier)
    blue:           Color(0xFF22C55E), // brand accent green
    blue700:        Color(0xFF4ADE80), // hover / pressed
    blue50:         Color(0xFF13291B), // selected-row / info tint (dark green surface)
    green:          Color(0xFF22C55E), // same as accent — gwgps uses one green for both
    green50:        Color(0xFF13291B),
    statusNormal:   Color(0xFF22C55E),
    statusInfo:     Color(0xFF38BDF8),
    statusWarning:  Color(0xFFF59E0B),
    statusCritical: Color(0xFFF04438),
  );

  // ── Light ────────────────────────────────────────────────────────────────────

  static const light = AppPalette(
    isDark:         false,
    bg:             Color(0xFFEDF1F4),
    surface1:       Color(0xFFFFFFFF), // panel-solid
    surface2:       Color(0xFFF6F7F9),
    surface3:       Color(0xFFEFF1F3),
    sidebarBg:      Color(0xFFFFFFFF),
    topbarBg:       Color(0xFFFFFFFF),
    border:         Color(0x1A0F1720), // rgba(15,23,32,.1)
    borderStrong:   Color(0x2E0F1720), // rgba(15,23,32,.18)
    divider:        Color(0x1A0F1720),
    text:           Color(0xFF10151B),
    textMute:       Color(0xFF586069), // gwgps --text-dim (1st tier)
    textDim:        Color(0xFF8B939C), // gwgps --text-mute (2nd tier)
    blue:           Color(0xFF22C55E), // brand accent green (same across themes in gwgps)
    blue700:        Color(0xFF16A34A), // accent-2 / pressed
    blue50:         Color(0xFFE8F9EE), // selected-row / info tint
    green:          Color(0xFF22C55E),
    green50:        Color(0xFFE8F9EE),
    statusNormal:   Color(0xFF22C55E),
    statusInfo:     Color(0xFF38BDF8),
    statusWarning:  Color(0xFFF59E0B),
    statusCritical: Color(0xFFF04438),
  );

  // ── Dormant fallback: original "BioTrack" blue theme, pre-gwgps port ──────────
  // Not wired into the theme switcher. Kept only so the old look can be restored
  // quickly if ever wanted again — not actively designed/maintained alongside
  // the gwgps palette above, so treat as a snapshot, not a supported option.

  static const classicBlueDark = AppPalette(
    isDark:         true,
    bg:             Color(0xFF0E1622),
    surface1:       Color(0xFF162133),
    surface2:       Color(0xFF1B273B),
    surface3:       Color(0xFF1F2D41),
    sidebarBg:      Color(0xFF0A1119),
    topbarBg:       Color(0xFF0E1622),
    border:         Color(0xFF243042),
    borderStrong:   Color(0xFF324158),
    divider:        Color(0xFF1C2840),
    text:           Color(0xFFEAF0F7),
    textMute:       Color(0xFF9DA9BB),
    textDim:        Color(0xFF6B7888),
    blue:           Color(0xFF5AA6E8),
    blue700:        Color(0xFF7FBCF0),
    blue50:         Color(0xFF18293D),
    green:          Color(0xFF3FC06E),
    green50:        Color(0xFF14301F),
    statusNormal:   Color(0xFF3FC06E),
    statusInfo:     Color(0xFF5AA6E8),
    statusWarning:  Color(0xFFECC05A),
    statusCritical: Color(0xFFF0726F),
  );

  // ── Neutral (color-rich, cool-tinted surfaces) ────────────────────────────────

  static const neutral = AppPalette(
    isDark:         false,
    bg:             Color(0xFFEAF1F4),
    surface1:       Color(0xFFFFFFFF),
    surface2:       Color(0xFFF2F7FA),
    surface3:       Color(0xFFE0EBF0),
    sidebarBg:      Color(0xFFFFFFFF),
    topbarBg:       Color(0xFFFFFFFF),
    border:         Color(0xFFD2E0E6),
    borderStrong:   Color(0xFFBBCDD6),
    divider:        Color(0xFFD8E6EC),
    text:           Color(0xFF14222C),
    textMute:       Color(0xFF51636E),
    textDim:        Color(0xFF8499A3),
    blue:           Color(0xFF22C55E),
    blue700:        Color(0xFF16A34A),
    blue50:         Color(0xFFDBF3E2),
    green:          Color(0xFF22C55E),
    green50:        Color(0xFFDBF3E2),
    statusNormal:   Color(0xFF22C55E),
    statusInfo:     Color(0xFF38BDF8),
    statusWarning:  Color(0xFFF59E0B),
    statusCritical: Color(0xFFF04438),
  );

  // ── Aurora (warm cream/gold canvas — the new default identity) ───────────────
  // Ported from a set of Crextio/Toota HR-dashboard mockups the user shared
  // for inspiration (2026-08-27): soft gray→gold diagonal wash, warm-white
  // cards, near-black text, golden primary accent. Set as the app default
  // (see themeNotifier below) rather than an opt-in extra — the user framed
  // this as a new system's identity, not a side option.

  static const aurora = AppPalette(
    isDark:         false,
    bg:             Color(0xFFF1EEE7), // flat fallback (Scaffold.backgroundColor)
    bgGradient:     [Color(0xFFEDEDED), Color(0xFFFCEFC7)], // topLeft → bottomRight wash
    surface1:       Color(0xFFFFFFFF), // cards, panel-solid
    surface2:       Color(0xFFF8F6EF), // inset panels, schedule bubbles
    surface3:       Color(0xFFF1EEE2), // inputs, nested surfaces
    sidebarBg:      Color(0xFFFFFFFF),
    topbarBg:       Color(0xFFFFFFFF),
    border:         Color(0x1A1C1712), // warm near-black @ ~10%
    borderStrong:   Color(0x2E1C1712), // warm near-black @ ~18%
    divider:        Color(0x1A1C1712),
    text:           Color(0xFF1C1712),
    textMute:       Color(0xFF6E6659),
    textDim:        Color(0xFF9D9686),
    blue:           Color(0xFFF2C230), // golden primary accent
    blue700:        Color(0xFFD9A916), // hover / pressed
    blue50:         Color(0xFFFBF0CC), // selected-row / info tint
    green:          Color(0xFF3FAE58),
    green50:        Color(0xFFDFF1DF),
    statusNormal:   Color(0xFF3FAE58),
    statusInfo:     Color(0xFF38BDF8),
    statusWarning:  Color(0xFFE8A63A),
    statusCritical: Color(0xFFE2574C),
  );

  // ── Hypermed (brand dark — sampled from the logo) ───────────────────────────
  // Brand blue 0xFF5088C8 and brand green 0xFF30A850 taken off the mark.
  // Green is already spoken for as "collected / money in", so blue carries
  // every primary action and active nav item — the two never compete.

  static const hypermed = AppPalette(
    isDark:         true,
    bg:             Color(0xFF0A0F16),
    surface1:       Color(0xFF131C26),
    surface2:       Color(0xFF1E2A38),
    surface3:       Color(0xFF243244),
    sidebarBg:      Color(0xFF0D141D),
    topbarBg:       Color(0xFF0D141D),
    border:         Color(0x1AE2ECF6), // rgba(226,236,246,.10)
    borderStrong:   Color(0x2EE2ECF6), // rgba(226,236,246,.18)
    divider:        Color(0x1AE2ECF6),
    text:           Color(0xFFEAF1F8),
    textMute:       Color(0xFF9FB0C2),
    textDim:        Color(0xFF6C7C8D),
    blue:           Color(0xFF5088C8), // brand blue — primary action
    blue700:        Color(0xFF84B2E4), // hover / pressed (lifts on dark)
    blue50:         Color(0xFF14263A), // selected-row tint
    green:          Color(0xFF30A850), // brand green — money in
    green50:        Color(0xFF10241A),
    statusNormal:   Color(0xFF30A850),
    statusInfo:     Color(0xFF5088C8),
    statusWarning:  Color(0xFFE0A63A),
    statusCritical: Color(0xFFE05252),
  );

  // ── Hypermed Light (brand on white) ─────────────────────────────────────────
  // Both brand hues darkened one step so they hold contrast for small type
  // on white: blue 0xFF5088C8 → 0xFF3C74B4, green 0xFF30A850 → 0xFF1F8A40.

  static const hypermedLight = AppPalette(
    isDark:         false,
    bg:             Color(0xFFE9EEF4),
    surface1:       Color(0xFFFFFFFF),
    surface2:       Color(0xFFF1F5F9),
    surface3:       Color(0xFFE4EBF2),
    sidebarBg:      Color(0xFFFFFFFF),
    topbarBg:       Color(0xFFFFFFFF),
    border:         Color(0x1A0D1926), // rgba(13,25,38,.10)
    borderStrong:   Color(0x2E0D1926),
    divider:        Color(0x1A0D1926),
    text:           Color(0xFF0D1926),
    textMute:       Color(0xFF48586A),
    textDim:        Color(0xFF83919F),
    blue:           Color(0xFF3C74B4),
    blue700:        Color(0xFF2F6099),
    blue50:         Color(0xFFE6EEF8),
    green:          Color(0xFF1F8A40),
    green50:        Color(0xFFE4F3E8),
    statusNormal:   Color(0xFF1F8A40),
    statusInfo:     Color(0xFF3C74B4),
    statusWarning:  Color(0xFFA5720C),
    statusCritical: Color(0xFFC0392B),
  );

  // ── Slate Dusk (cool, corporate) ────────────────────────────────────────────
  // Blue-grey panels on a deep navy ground; indigo actions, cyan for charts.

  static const slateDusk = AppPalette(
    isDark:         true,
    bg:             Color(0xFF0B0F17),
    surface1:       Color(0xFF141A26),
    surface2:       Color(0xFF1E2637),
    surface3:       Color(0xFF243046),
    sidebarBg:      Color(0xFF0D1220),
    topbarBg:       Color(0xFF0D1220),
    border:         Color(0x24949FB8), // rgba(148,163,184,.14)
    borderStrong:   Color(0x42949FB8), // rgba(148,163,184,.26)
    divider:        Color(0x24949FB8),
    text:           Color(0xFFEEF2F8),
    textMute:       Color(0xFFA6B2C4),
    textDim:        Color(0xFF6E7C91),
    blue:           Color(0xFF6366F1),
    blue700:        Color(0xFFA5B4FC),
    blue50:         Color(0xFF1C1E3D),
    green:          Color(0xFF34D399),
    green50:        Color(0xFF10281F),
    statusNormal:   Color(0xFF34D399),
    statusInfo:     Color(0xFF38BDF8),
    statusWarning:  Color(0xFFFBBF24),
    statusCritical: Color(0xFFFB7185),
  );

  // ── Ledger Paper (warm light, print-adjacent) ───────────────────────────────
  // Warm off-white sheets on a soft grey desk, ink-dark type, deep green
  // accent. Reds and ambers are the darker print-safe steps.

  static const ledgerPaper = AppPalette(
    isDark:         false,
    bg:             Color(0xFFEFEDE7),
    surface1:       Color(0xFFFFFFFF),
    surface2:       Color(0xFFF5F3EE),
    surface3:       Color(0xFFE9E6DF),
    sidebarBg:      Color(0xFFFBFAF7),
    topbarBg:       Color(0xFFFBFAF7),
    border:         Color(0x1A181C22), // rgba(24,28,34,.10)
    borderStrong:   Color(0x2E181C22),
    divider:        Color(0x1A181C22),
    text:           Color(0xFF181C22),
    textMute:       Color(0xFF535A63),
    textDim:        Color(0xFF8A9099),
    blue:           Color(0xFF15803D),
    blue700:        Color(0xFF116632),
    blue50:         Color(0xFFE4F0E8),
    green:          Color(0xFF15803D),
    green50:        Color(0xFFE4F0E8),
    statusNormal:   Color(0xFF15803D),
    statusInfo:     Color(0xFF0E7490),
    statusWarning:  Color(0xFFB45309),
    statusCritical: Color(0xFFB42318),
  );

  // ── Carbon Amber (warm high contrast) ───────────────────────────────────────
  // Pure neutral carbon; amber is the ACTION colour only — warnings use red,
  // so the two never blur. Highest contrast of the set.

  static const carbonAmber = AppPalette(
    isDark:         true,
    bg:             Color(0xFF0A0A0A),
    surface1:       Color(0xFF161616),
    surface2:       Color(0xFF232323),
    surface3:       Color(0xFF2B2B2B),
    sidebarBg:      Color(0xFF0F0F0F),
    topbarBg:       Color(0xFF0F0F0F),
    border:         Color(0x17FFFFFF), // rgba(255,255,255,.09)
    borderStrong:   Color(0x2EFFFFFF), // rgba(255,255,255,.18)
    divider:        Color(0x17FFFFFF),
    text:           Color(0xFFFAFAF9),
    textMute:       Color(0xFFB0AEA9),
    textDim:        Color(0xFF7A7873),
    blue:           Color(0xFFF59E0B),
    blue700:        Color(0xFFFBBF24),
    blue50:         Color(0xFF2B1F08),
    green:          Color(0xFF4ADE80),
    green50:        Color(0xFF12291B),
    statusNormal:   Color(0xFF4ADE80),
    statusInfo:     Color(0xFF2DD4BF),
    statusWarning:  Color(0xFFF59E0B),
    statusCritical: Color(0xFFEF4444),
  );

  // ── Nocturne (the bound web design system's tokens) ─────────────────────────
  // Near-neutral blue-grey ground, blurple accent used as line and glow.
  // Chroma stays low outside the accent, so financial reds/ambers carry.

  static const nocturne = AppPalette(
    isDark:         true,
    bg:             Color(0xFF161826),
    surface1:       Color(0xFF1F2133),
    surface2:       Color(0xFF2A2D42),
    surface3:       Color(0xFF32354D),
    sidebarBg:      Color(0xFF1A1C2C),
    topbarBg:       Color(0xFF1A1C2C),
    border:         Color(0x1CE9E9ED), // rgba(233,233,237,.11)
    borderStrong:   Color(0x739184D9), // accent @ ~45% — this system borders with the accent
    divider:        Color(0x1CE9E9ED),
    text:           Color(0xFFE9E9ED),
    textMute:       Color(0xFFA8A8B8),
    textDim:        Color(0xFF74748A),
    blue:           Color(0xFF9184D9),
    blue700:        Color(0xFFB8AEEA),
    blue50:         Color(0xFF272444),
    green:          Color(0xFF6EE7A8),
    green50:        Color(0xFF142C22),
    statusNormal:   Color(0xFF6EE7A8),
    statusInfo:     Color(0xFF7FC4E8),
    statusWarning:  Color(0xFFE0A863),
    statusCritical: Color(0xFFF27272),
  );

  // ── Daylight (cool light, high legibility) ──────────────────────────────────
  // Neutral grey-blue light scheme — no warmth, easiest of the light options
  // for long stretches on dense tables.

  static const daylight = AppPalette(
    isDark:         false,
    bg:             Color(0xFFEBEEF3),
    surface1:       Color(0xFFFFFFFF),
    surface2:       Color(0xFFF2F5F9),
    surface3:       Color(0xFFE4E9F1),
    sidebarBg:      Color(0xFFFFFFFF),
    topbarBg:       Color(0xFFFFFFFF),
    border:         Color(0x1A0F172A), // rgba(15,23,42,.10)
    borderStrong:   Color(0x2E0F172A),
    divider:        Color(0x1A0F172A),
    text:           Color(0xFF0F172A),
    textMute:       Color(0xFF4A5568),
    textDim:        Color(0xFF8492A6),
    blue:           Color(0xFF4338CA),
    blue700:        Color(0xFF362CA6),
    blue50:         Color(0xFFE8E6F8),
    green:          Color(0xFF047857),
    green50:        Color(0xFFDFF0EA),
    statusNormal:   Color(0xFF047857),
    statusInfo:     Color(0xFF0369A1),
    statusWarning:  Color(0xFFA16207),
    statusCritical: Color(0xFFBE123C),
  );

  // ── Forest Deep (dark, single-hue calm) ─────────────────────────────────────
  // Green-black ground with mint accent — one hue from surface to action.
  // Kindest at night; red and amber are the only real colour on screen.

  static const forestDeep = AppPalette(
    isDark:         true,
    bg:             Color(0xFF06100C),
    surface1:       Color(0xFF0E1B15),
    surface2:       Color(0xFF16281F),
    surface3:       Color(0xFF1C3227),
    sidebarBg:      Color(0xFF08140F),
    topbarBg:       Color(0xFF08140F),
    border:         Color(0x1ABEF2D7), // rgba(190,242,215,.10)
    borderStrong:   Color(0x33BEF2D7), // rgba(190,242,215,.20)
    divider:        Color(0x1ABEF2D7),
    text:           Color(0xFFEAF5EE),
    textMute:       Color(0xFF9BB4A6),
    textDim:        Color(0xFF698375),
    blue:           Color(0xFF34D399),
    blue700:        Color(0xFF6EE7B7),
    blue50:         Color(0xFF102A20),
    green:          Color(0xFF34D399),
    green50:        Color(0xFF102A20),
    statusNormal:   Color(0xFF34D399),
    statusInfo:     Color(0xFF5EEAD4),
    statusWarning:  Color(0xFFFCD34D),
    statusCritical: Color(0xFFFB7185),
  );

  // ── Ink & Copper (warm dark, editorial) ─────────────────────────────────────
  // Copper is the ACTION colour; amber is reserved strictly for "owed", since
  // the two are near neighbours.

  static const inkCopper = AppPalette(
    isDark:         true,
    bg:             Color(0xFF100D0B),
    surface1:       Color(0xFF1C1715),
    surface2:       Color(0xFF2A2320),
    surface3:       Color(0xFF332B27),
    sidebarBg:      Color(0xFF161211),
    topbarBg:       Color(0xFF161211),
    border:         Color(0x1AF5ECE1), // rgba(245,236,225,.10)
    borderStrong:   Color(0x2EF5ECE1), // rgba(245,236,225,.18)
    divider:        Color(0x1AF5ECE1),
    text:           Color(0xFFF5ECE1),
    textMute:       Color(0xFFB5A79A),
    textDim:        Color(0xFF7E736A),
    blue:           Color(0xFFC97B4A),
    blue700:        Color(0xFFE0A177),
    blue50:         Color(0xFF2E1D13),
    green:          Color(0xFF7CC49A),
    green50:        Color(0xFF16281F),
    statusNormal:   Color(0xFF7CC49A),
    statusInfo:     Color(0xFF6FA8B8),
    statusWarning:  Color(0xFFD9A02B),
    statusCritical: Color(0xFFE05252),
  );

  // ── Accessor ──────────────────────────────────────────────────────────────────

  static AppPalette of(BuildContext ctx) =>
      Theme.of(ctx).extension<AppPalette>() ?? dark;

  // ── ThemeExtension boilerplate ────────────────────────────────────────────────

  @override
  AppPalette copyWith({
    Color? bg, Color? surface1, Color? surface2, Color? surface3,
    Color? sidebarBg, Color? topbarBg,
    Color? border, Color? borderStrong, Color? divider,
    Color? text, Color? textMute, Color? textDim,
    Color? blue, Color? blue700, Color? blue50,
    Color? green, Color? green50,
    Color? statusNormal, Color? statusInfo, Color? statusWarning, Color? statusCritical,
    bool? isDark,
    List<Color>? bgGradient,
  }) => AppPalette(
    bg:             bg             ?? this.bg,
    bgGradient:     bgGradient     ?? this.bgGradient,
    surface1:       surface1       ?? this.surface1,
    surface2:       surface2       ?? this.surface2,
    surface3:       surface3       ?? this.surface3,
    sidebarBg:      sidebarBg      ?? this.sidebarBg,
    topbarBg:       topbarBg       ?? this.topbarBg,
    border:         border         ?? this.border,
    borderStrong:   borderStrong   ?? this.borderStrong,
    divider:        divider        ?? this.divider,
    text:           text           ?? this.text,
    textMute:       textMute       ?? this.textMute,
    textDim:        textDim        ?? this.textDim,
    blue:           blue           ?? this.blue,
    blue700:        blue700        ?? this.blue700,
    blue50:         blue50         ?? this.blue50,
    green:          green          ?? this.green,
    green50:        green50        ?? this.green50,
    statusNormal:   statusNormal   ?? this.statusNormal,
    statusInfo:     statusInfo     ?? this.statusInfo,
    statusWarning:  statusWarning  ?? this.statusWarning,
    statusCritical: statusCritical ?? this.statusCritical,
    isDark:         isDark         ?? this.isDark,
  );

  @override
  AppPalette lerp(AppPalette other, double t) => AppPalette(
    isDark:         t < 0.5 ? isDark : other.isDark,
    bgGradient:     t < 0.5 ? bgGradient : other.bgGradient,
    bg:             Color.lerp(bg,             other.bg,             t)!,
    surface1:       Color.lerp(surface1,       other.surface1,       t)!,
    surface2:       Color.lerp(surface2,       other.surface2,       t)!,
    surface3:       Color.lerp(surface3,       other.surface3,       t)!,
    sidebarBg:      Color.lerp(sidebarBg,      other.sidebarBg,      t)!,
    topbarBg:       Color.lerp(topbarBg,       other.topbarBg,       t)!,
    border:         Color.lerp(border,         other.border,         t)!,
    borderStrong:   Color.lerp(borderStrong,   other.borderStrong,   t)!,
    divider:        Color.lerp(divider,        other.divider,        t)!,
    text:           Color.lerp(text,           other.text,           t)!,
    textMute:       Color.lerp(textMute,       other.textMute,       t)!,
    textDim:        Color.lerp(textDim,        other.textDim,        t)!,
    blue:           Color.lerp(blue,           other.blue,           t)!,
    blue700:        Color.lerp(blue700,        other.blue700,        t)!,
    blue50:         Color.lerp(blue50,         other.blue50,         t)!,
    green:          Color.lerp(green,          other.green,          t)!,
    green50:        Color.lerp(green50,        other.green50,        t)!,
    statusNormal:   Color.lerp(statusNormal,   other.statusNormal,   t)!,
    statusInfo:     Color.lerp(statusInfo,     other.statusInfo,     t)!,
    statusWarning:  Color.lerp(statusWarning,  other.statusWarning,  t)!,
    statusCritical: Color.lerp(statusCritical, other.statusCritical, t)!,
  );
}

/// `context.pal.bg`  is shorter than  `AppPalette.of(context).bg`
extension AppPaletteX on BuildContext {
  AppPalette get pal => AppPalette.of(this);
}

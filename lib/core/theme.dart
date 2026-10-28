import 'package:flutter/material.dart';

/// VidyaDesk design system — colours.
///
/// Field names stay the same as before so every screen keeps working:
///   brand   = Iris (main purple)        success = Mint  (present / paid)
///   indigo  = Sky  (info / blue)        warn    = Amber (pending)
///   accent  = Amber (highlights)        danger  = Rose  (absent / due)
class Palette {
  const Palette({
    required this.dark,
    required this.bg,
    required this.top,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.brand,
    required this.brand2,
    required this.brandDeep,
    required this.brandTint,
    required this.accent,
    required this.success,
    required this.successTint,
    required this.danger,
    required this.dangerTint,
    required this.warn,
    required this.warnTint,
    required this.indigo,
    required this.indigoTint,
  });

  final bool dark;
  final Color bg, top, card, cardAlt, border, ink, ink2, muted;
  final Color brand, brand2, brandDeep, brandTint, accent;
  final Color success, successTint, danger, dangerTint, warn, warnTint;
  final Color indigo, indigoTint;

  static const light = Palette(
    dark: false,
    bg: Color(0xFFF6F5FB),
    top: Color(0xFFECE8FF),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF8F7FD),
    border: Color(0xFFECEAF5),
    ink: Color(0xFF17153A),
    ink2: Color(0xFF47446A),
    muted: Color(0xFF8A87A6),
    brand: Color(0xFF6C5CE7),
    brand2: Color(0xFF8B7CF6),
    brandDeep: Color(0xFF4B3FC4),
    brandTint: Color(0xFFEFEDFF),
    accent: Color(0xFFE8930C),
    success: Color(0xFF12B886),
    successTint: Color(0xFFE3F8F0),
    danger: Color(0xFFF0466E),
    dangerTint: Color(0xFFFDE8EE),
    warn: Color(0xFFE8930C),
    warnTint: Color(0xFFFFF4DB),
    indigo: Color(0xFF3B9EF5),
    indigoTint: Color(0xFFE5F2FE),
  );

  static const night = Palette(
    dark: true,
    bg: Color(0xFF0F0E1A),
    top: Color(0xFF1B1835),
    card: Color(0xFF191829),
    cardAlt: Color(0xFF201F33),
    border: Color(0xFF2A2842),
    ink: Color(0xFFF2F1FA),
    ink2: Color(0xFFC9C6E0),
    muted: Color(0xFF8E8BAA),
    brand: Color(0xFF8B7CFF),
    brand2: Color(0xFFA79BFF),
    brandDeep: Color(0xFF6C5CE7),
    brandTint: Color(0xFF26224A),
    accent: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    successTint: Color(0xFF143329),
    danger: Color(0xFFFB7193),
    dangerTint: Color(0xFF3A1A26),
    warn: Color(0xFFFBBF24),
    warnTint: Color(0xFF33290F),
    indigo: Color(0xFF60B4FA),
    indigoTint: Color(0xFF14283D),
  );

  /// Purple feature-card gradient (balance card, next class, ID card).
  LinearGradient get hero => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7A6AF0), Color(0xFF5545D6)],
      );

  /// Main button gradient.
  LinearGradient get button => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [brand2, brand]);

  /// Soft lavender wash behind the top of every page.
  LinearGradient get pageTop => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bg]);

  LinearGradient get gold => const LinearGradient(colors: [Color(0xFFFFC870), Color(0xFFF59F00)]);

  List<BoxShadow> get shadow => dark
      ? const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -14),
        ]
      : const [
          BoxShadow(color: Color(0x0A17153A), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x384C3FC4), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -14),
        ];

  List<BoxShadow> glow(Color c) => [BoxShadow(color: c.withValues(alpha: .45), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -12)];
}

extension PaletteX on BuildContext {
  Palette get pal => Theme.of(this).brightness == Brightness.dark ? Palette.night : Palette.light;
}

/// Spacing and corner sizes used everywhere.
class Gap {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 20, xxl = 28;
  static const double rCard = 22, rTile = 13, rInput = 15, rButton = 16;
  static const double page = 18;
}

ThemeData buildTheme(Palette p, {bool hindi = false}) {
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final family = hindi ? 'NotoDeva' : 'Hanken';
  const fallback = ['Hanken', 'NotoDeva'];
  final text = base.textTheme.apply(fontFamily: family, fontFamilyFallback: fallback, bodyColor: p.ink, displayColor: p.ink);
  OutlineInputBorder ob(Color c, [double w = 1.5]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(Gap.rInput), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: base.colorScheme.copyWith(primary: p.brand, secondary: p.accent, surface: p.card, onSurface: p.ink, error: p.danger),
    textTheme: text,
    dividerColor: p.border,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 21, fontWeight: FontWeight.w800, color: p.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
      prefixIconColor: p.muted,
      border: ob(p.border),
      enabledBorder: ob(p.border),
      focusedBorder: ob(p.brand, 2),
      errorBorder: ob(p.danger),
      focusedErrorBorder: ob(p.danger, 2),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.card,
      selectedColor: p.brandTint,
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w700, color: p.ink2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? const Color(0xFFF2F1FA) : const Color(0xFF17153A),
      contentTextStyle: TextStyle(fontFamily: family, color: p.dark ? const Color(0xFF17153A) : Colors.white, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      showDragHandle: true,
      dragHandleColor: p.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: p.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.brand, textStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w700))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand),
    timePickerTheme: TimePickerThemeData(backgroundColor: p.card),
    datePickerTheme: DatePickerThemeData(backgroundColor: p.card),
  );
}

import 'package:flutter/material.dart';

/// Colours used across the app. One set for light mode, one for dark mode.
class Palette {
  const Palette({
    required this.dark,
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brand,
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
  final Color bg, card, cardAlt, border, ink, muted;
  final Color brand, brandDeep, brandTint, accent;
  final Color success, successTint, danger, dangerTint, warn, warnTint;
  final Color indigo, indigoTint;

  static const light = Palette(
    dark: false,
    bg: Color(0xFFF3F6F5),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF7F9F8),
    border: Color(0xFFE1E7E5),
    ink: Color(0xFF0E1726),
    muted: Color(0xFF5A6577),
    brand: Color(0xFF0C5C61),
    brandDeep: Color(0xFF073B3F),
    brandTint: Color(0xFFE2F0EF),
    accent: Color(0xFFF5A524),
    success: Color(0xFF15803D),
    successTint: Color(0xFFE3F5EA),
    danger: Color(0xFFC2281D),
    dangerTint: Color(0xFFFDECEA),
    warn: Color(0xFF8A5300),
    warnTint: Color(0xFFFEF3DC),
    indigo: Color(0xFF4338CA),
    indigoTint: Color(0xFFEEF0FF),
  );

  static const night = Palette(
    dark: true,
    bg: Color(0xFF0B1220),
    card: Color(0xFF141C2E),
    cardAlt: Color(0xFF1A2337),
    border: Color(0xFF243049),
    ink: Color(0xFFE6EBF5),
    muted: Color(0xFF94A3B8),
    brand: Color(0xFF5ED6C8),
    brandDeep: Color(0xFF0F2A2E),
    brandTint: Color(0xFF16343A),
    accent: Color(0xFFFFC861),
    success: Color(0xFF86EFAC),
    successTint: Color(0x2622C55E),
    danger: Color(0xFFFCA5A5),
    dangerTint: Color(0x26EF4444),
    warn: Color(0xFFFDE68A),
    warnTint: Color(0x26F59E0B),
    indigo: Color(0xFFA5B4FC),
    indigoTint: Color(0x266366F1),
  );

  /// Header gradient (teal) used on the big top areas.
  LinearGradient get hero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark ? const [Color(0xFF134E4A), Color(0xFF0F2A2E)] : const [Color(0xFF0E6A70), Color(0xFF073B3F)],
      );

  LinearGradient get gold => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFC861), Color(0xFFE08A0B)],
      );

  List<BoxShadow> get shadow => dark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -12)]
      : const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x240F172A), blurRadius: 28, offset: Offset(0, 12), spreadRadius: -14),
        ];
}

extension PaletteX on BuildContext {
  Palette get pal => Theme.of(this).brightness == Brightness.dark ? Palette.night : Palette.light;
}

ThemeData buildTheme(Palette p, {bool hindi = false}) {
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final family = hindi ? 'NotoDeva' : 'Hanken';
  final text = base.textTheme.apply(
    fontFamily: family,
    fontFamilyFallback: const ['Hanken', 'NotoDeva'],
    bodyColor: p.ink,
    displayColor: p.ink,
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: p.brand,
      secondary: p.accent,
      surface: p.card,
      onSurface: p.ink,
      error: p.danger,
    ),
    textTheme: text,
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: family, fontFamilyFallback: const ['Hanken', 'NotoDeva'], fontSize: 20, fontWeight: FontWeight.w800, color: p.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.cardAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.brand, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.danger)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? const Color(0xFFE6EBF5) : const Color(0xFF0E1726),
      contentTextStyle: TextStyle(fontFamily: family, color: p.dark ? const Color(0xFF0E1726) : Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, showDragHandle: true),
    dialogTheme: DialogThemeData(backgroundColor: p.card),
  );
}

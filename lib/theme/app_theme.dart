import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Палитры EM-Power: тёмная (основная, по референс-макету) и светлая.
/// Тёмная: фон чистый чёрный, карточка ~#0C0F13, акцент #FFCC00.
/// Светлая — зеркальная по контрасту; акцент и статусные цвета общие.
class _Palette {
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color ringTrack;
  final Color textPrimary;
  final Color textSecondary;
  final Color textLabel;

  const _Palette({
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.ringTrack,
    required this.textPrimary,
    required this.textSecondary,
    required this.textLabel,
  });
}

const _dark = _Palette(
  bg: Color(0xFF000000), // чистый чёрный — максимальный контраст/резкость
  card: Color(0xFF0C0F13),
  cardBorder: Color(0xFF161B22), // едва заметная рамка
  ringTrack: Color(0xFF20262E),
  textPrimary: Color(0xFFF2F4F7),
  textSecondary: Color(0xFF8A909A),
  textLabel: Color(0xFF6C7480),
);

const _light = _Palette(
  bg: Color(0xFFF4F5F7),
  card: Color(0xFFFFFFFF),
  cardBorder: Color(0xFFE2E5EA),
  ringTrack: Color(0xFFE4E7EC),
  textPrimary: Color(0xFF14181E),
  textSecondary: Color(0xFF5B6470),
  textLabel: Color(0xFF7C8592),
);

/// Активные цвета приложения. Переключаются [apply] при смене темы —
/// весь UI читает эти поля при build, поэтому после смены палитры
/// у корня дерево перерисовывается уже в новых цветах.
class AppColors {
  static _Palette _p = _dark;
  static bool isDark = true;

  static void apply({required bool dark}) {
    isDark = dark;
    _p = dark ? _dark : _light;
  }

  static Color get bg => _p.bg;
  static Color get card => _p.card;
  static Color get cardBorder => _p.cardBorder;
  static Color get ringTrack => _p.ringTrack;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textLabel => _p.textLabel;

  // Общие для обеих тем
  static const accent = Color(0xFFFFCC00); // фирменный жёлтый

  // Кольцо SOC (вся дуга одним цветом по интервалу банка)
  static const socGreen = Color(0xFF6FD12A);
  static const socYellow = Color(0xFFFFCC00);
  static const socRed = Color(0xFFE5484D);

  // Текст статуса
  static const statusCharge = Color(0xFF6FD12A);
  static const statusDischarge = Color(0xFFF5A623); // оранжево-янтарный (не красный)
  static const statusStandby = Color(0xFF9AA0A8);

  static const bluetooth = Color(0xFF2A7FD1);
}

class AppTheme {
  static ThemeData of({required bool dark}) {
    final base = dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final p = dark ? _dark : _light;
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        surface: p.card,
        secondary: AppColors.accent,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      dividerColor: p.cardBorder,
    );
  }
}

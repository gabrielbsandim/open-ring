import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  const new({
    required this.background,
    required this.surface,
    required this.surfaceBorder,
    required this.surfaceInner,
    required this.strongBorder,
    required this.track,
    required this.navBar,
    required this.textPrimary,
    required this.textSecondary,
    required this.textLabel,
    required this.sleep,
    required this.heart,
    required this.activity,
    required this.oxygen,
    required this.stress,
    required this.onAccent,
    required this.sleepAwake,
    required this.sleepRem,
    required this.sleepLight,
    required this.sleepDeep,
  });

  static const dark = AppColors(
    background: Color(0xFF0E0F13),
    surface: Color(0xFF171920),
    surfaceBorder: Color(0xFF242833),
    surfaceInner: Color(0xFF1F222B),
    strongBorder: Color(0xFF2E3340),
    track: Color(0xFF262A34),
    navBar: Color(0xFF12141A),
    textPrimary: Color(0xFFECEEF2),
    textSecondary: Color(0xFFC9CED8),
    textLabel: Color(0xFF9AA1AE),
    sleep: Color(0xFFA78BFA),
    heart: Color(0xFFFF7A6B),
    activity: Color(0xFF4ADE80),
    oxygen: Color(0xFF22D3EE),
    stress: Color(0xFFFBBF24),
    onAccent: Color(0xFF0E0F13),
    sleepAwake: Color(0xFFE5E7EB),
    sleepRem: Color(0xFFC4B5FD),
    sleepLight: Color(0xFF8B6CF0),
    sleepDeep: Color(0xFF6D50E6),
  );

  static const light = AppColors(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceBorder: Color(0xFFE3E6EC),
    surfaceInner: Color(0xFFEEF0F4),
    strongBorder: Color(0xFFCDD2DB),
    track: Color(0xFFE3E6EC),
    navBar: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF14161C),
    textSecondary: Color(0xFF3D4350),
    textLabel: Color(0xFF5A6170),
    sleep: Color(0xFF6D4FD8),
    heart: Color(0xFFC8372B),
    activity: Color(0xFF15803D),
    oxygen: Color(0xFF0E7490),
    stress: Color(0xFFB45309),
    onAccent: Color(0xFFFFFFFF),
    sleepAwake: Color(0xFF9CA3AF),
    sleepRem: Color(0xFFA78BFA),
    sleepLight: Color(0xFF7C5CE6),
    sleepDeep: Color(0xFF4C2FB8),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  final Color background;
  final Color surface;
  final Color surfaceBorder;
  final Color surfaceInner;
  final Color strongBorder;
  final Color track;
  final Color navBar;
  final Color textPrimary;
  final Color textSecondary;
  final Color textLabel;
  final Color sleep;
  final Color heart;
  final Color activity;
  final Color oxygen;
  final Color stress;
  final Color onAccent;
  final Color sleepAwake;
  final Color sleepRem;
  final Color sleepLight;
  final Color sleepDeep;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceBorder,
    Color? surfaceInner,
    Color? strongBorder,
    Color? track,
    Color? navBar,
    Color? textPrimary,
    Color? textSecondary,
    Color? textLabel,
    Color? sleep,
    Color? heart,
    Color? activity,
    Color? oxygen,
    Color? stress,
    Color? onAccent,
    Color? sleepAwake,
    Color? sleepRem,
    Color? sleepLight,
    Color? sleepDeep,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceBorder: surfaceBorder ?? this.surfaceBorder,
    surfaceInner: surfaceInner ?? this.surfaceInner,
    strongBorder: strongBorder ?? this.strongBorder,
    track: track ?? this.track,
    navBar: navBar ?? this.navBar,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textLabel: textLabel ?? this.textLabel,
    sleep: sleep ?? this.sleep,
    heart: heart ?? this.heart,
    activity: activity ?? this.activity,
    oxygen: oxygen ?? this.oxygen,
    stress: stress ?? this.stress,
    onAccent: onAccent ?? this.onAccent,
    sleepAwake: sleepAwake ?? this.sleepAwake,
    sleepRem: sleepRem ?? this.sleepRem,
    sleepLight: sleepLight ?? this.sleepLight,
    sleepDeep: sleepDeep ?? this.sleepDeep,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceBorder: mix(surfaceBorder, other.surfaceBorder),
      surfaceInner: mix(surfaceInner, other.surfaceInner),
      strongBorder: mix(strongBorder, other.strongBorder),
      track: mix(track, other.track),
      navBar: mix(navBar, other.navBar),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textLabel: mix(textLabel, other.textLabel),
      sleep: mix(sleep, other.sleep),
      heart: mix(heart, other.heart),
      activity: mix(activity, other.activity),
      oxygen: mix(oxygen, other.oxygen),
      stress: mix(stress, other.stress),
      onAccent: mix(onAccent, other.onAccent),
      sleepAwake: mix(sleepAwake, other.sleepAwake),
      sleepRem: mix(sleepRem, other.sleepRem),
      sleepLight: mix(sleepLight, other.sleepLight),
      sleepDeep: mix(sleepDeep, other.sleepDeep),
    );
  }
}

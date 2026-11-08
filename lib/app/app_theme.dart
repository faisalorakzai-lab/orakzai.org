import 'package:flutter/material.dart';

/// ORAKZAI.ORG brand palette: emerald, gold and ivory. Legacy identifiers
/// (navy, ...) remain as aliases so every shared screen inherits the system.
class AppColors {
  const AppColors._();

  // Core direction
  static const navy = Color(0xFF0F4A3A);
  static const navySoft = Color(0xFF1D6650);
  static const navyDeep = Color(0xFF08302A);
  static const gold = Color(0xFFC2A15E);
  static const goldDeep = Color(0xFF8A6A2E);
  static const goldWash = Color(0xFFF4EBD8);
  static const canvas = Color(0xFFF7F3EA);
  static const surface = Color(0xFFFFFDF8);
  static const onDark = Color(0xFFF8F6F1);
  static const ink = Color(0xFF15281F);
  static const muted = Color(0xFF5D6B62);
  static const line = Color(0xFFE6DFCF);
  static const blue = Color(0xFF3F6E9E);
  static const blueWash = Color(0xFFE9F2EC);
  static const green = Color(0xFF2B6F52);
  static const greenWash = Color(0xFFE6F1EA);
  static const danger = Color(0xFFA9483F);
  static const dangerWash = Color(0xFFFCEFED);

  // Compatibility aliases
  static const emerald = navy;
  static const emeraldSoft = navySoft;
  static const emeraldDeep = navyDeep;
  static const ivory = onDark;
}

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Manrope';
  static const fallback = ['NotoSansArabic'];

  /// Dark appearance: deep emerald surfaces with ivory text and gold accents.
  static ThemeData get dark {
    final base = light;
    const bg = Color(0xFF0A1F19);
    const card = Color(0xFF12302A);
    const text = Color(0xFFF1ECDF);
    const sub = Color(0xFFB9C2B8);
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: AppColors.gold,
      onPrimary: AppColors.navyDeep,
      surface: card,
      onSurface: text,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: card,
      surfaceContainerHigh: const Color(0xFF1A3D35),
      outline: const Color(0xFF2B4D44),
      outlineVariant: const Color(0xFF2B4D44),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme
          .apply(bodyColor: text, displayColor: text)
          .copyWith(
            bodyMedium: base.textTheme.bodyMedium?.copyWith(color: sub),
            bodySmall: base.textTheme.bodySmall?.copyWith(color: sub),
          ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: bg,
        foregroundColor: text,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(color: text),
      ),
      cardTheme: base.cardTheme.copyWith(color: card),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: card,
        titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(color: text),
        contentTextStyle: base.dialogTheme.contentTextStyle?.copyWith(
          color: text,
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: card),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: AppColors.gold,
        titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
          color: text,
        ),
        subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
          color: sub,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(fillColor: card),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: card,
      ),
      dividerColor: const Color(0xFF2B4D44),
    );
  }

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.emerald,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.emerald,
          onPrimary: AppColors.ivory,
          primaryContainer: AppColors.blueWash,
          onPrimaryContainer: AppColors.emeraldDeep,
          secondary: AppColors.gold,
          onSecondary: AppColors.ink,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          surfaceContainerLowest: AppColors.surface,
          surfaceContainerLow: AppColors.canvas,
          surfaceContainer: AppColors.canvas,
          surfaceContainerHigh: const Color(0xFFEFE9DC),
          outline: AppColors.line,
          outlineVariant: AppColors.line,
          error: AppColors.danger,
        );

    const text = TextTheme(
      headlineLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
      ),
      headlineMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 15.5,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        color: AppColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: AppColors.ink, fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );

    final radius12 = BorderRadius.circular(12);
    final buttonShape = RoundedRectangleBorder(borderRadius: radius12);

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fallback,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.emerald,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.ivory,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fallback,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.emerald,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.emerald,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: AppColors.line, width: 1.2),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fallback,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.emerald,
          minimumSize: const Size(48, 44),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fallback,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.emerald),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.ivory,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.emerald,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.muted,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.goldWash,
        side: const BorderSide(color: AppColors.line),
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(
          color: AppColors.emerald,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ink,
          fontSize: 14.5,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.line,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fallback,
          color: AppColors.ivory,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      dividerColor: AppColors.line,
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.emerald,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.goldWash,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        height: 70,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.emerald
                : AppColors.muted,
            size: 23,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fallback,
            fontSize: 11.5,
            letterSpacing: 0.2,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.emerald
                : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

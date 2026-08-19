import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// The one place Material is told what Classy Closet looks like.
///
/// Every widget in the app inherits from here rather than styling itself, so
/// the whole interface follows one file. The scheme is built by hand instead of
/// from a seed: `fromSeed` would harmonise the gold into something safe and
/// generic, and the gold is the point.
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.brand,
      onPrimary: AppColors.brandInk,
      primaryContainer: AppColors.brandRaised,
      onPrimaryContainer: AppColors.brandInk,
      secondary: AppColors.gold,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.goldWash,
      onSecondaryContainer: AppColors.goldDeep,
      tertiary: AppColors.goldDeep,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerWash,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surfaceAlt,
      surfaceContainer: AppColors.surfaceAlt,
      surfaceContainerHigh: AppColors.bg,
      surfaceContainerHighest: AppColors.bg,
      onSurfaceVariant: AppColors.inkSoft,
      outline: AppColors.border,
      outlineVariant: AppColors.borderSoft,
      shadow: Color(0x1A1A1712),
      scrim: Color(0x99000000),
      inverseSurface: AppColors.brand,
      onInverseSurface: AppColors.brandInkSoft,
      inversePrimary: AppColors.brandInk,
    );

    final textTheme = AppTypography.textTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: textTheme,
      fontFamily: AppTypography.sans,
      visualDensity: VisualDensity.compact,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardBorder,
          side: BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
        space: 1,
      ),

      // ------------------------------------------------------------- inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.base,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkFaint),
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.inkSoft),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.goldDeep,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
        prefixIconColor: AppColors.inkFaint,
        suffixIconColor: AppColors.inkFaint,
        border: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.border),
        ),
        // Gold on focus, everywhere, so the caret is never in doubt.
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.gold, width: 1.6),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.danger, width: 1.6),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
      ),

      // ------------------------------------------------------------ buttons
      // The default filled button is the dark brand one; gold is reserved for
      // the single most important action on a screen and is applied by
      // AccentButton rather than being the default.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.brandInk,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.inkFaint,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.inputBorder,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.brandInk,
          elevation: 0,
          minimumSize: const Size(0, 40),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.inputBorder,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.inputBorder,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.goldDeep,
          minimumSize: const Size(0, 40),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.inputBorder,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.inkSoft,
          hoverColor: AppColors.surfaceAlt,
        ),
      ),

      // ------------------------------------------------------------- chrome
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.inkSoft,
          selectedBackgroundColor: AppColors.brand,
          selectedForegroundColor: AppColors.brandInk,
          side: const BorderSide(color: AppColors.border),
          textStyle: textTheme.labelMedium,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.inputBorder,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        side: const BorderSide(color: AppColors.border),
        labelStyle: textTheme.labelSmall!.copyWith(color: AppColors.inkSoft),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.pillBorder),
      ),

      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(AppColors.surfaceAlt),
        headingTextStyle: AppTypography.microLabel.copyWith(
          color: AppColors.inkFaint,
        ),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
        horizontalMargin: AppSpacing.lg,
        columnSpacing: AppSpacing.xxl,
        headingRowHeight: 40,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          color: AppColors.ink,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.ink),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.cardBorder,
          side: BorderSide(color: AppColors.border),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.brand,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.brandInkSoft,
        ),
        actionTextColor: AppColors.brandInk,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.inputBorder),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.surface),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.gold
              : AppColors.border,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.gold
              : AppColors.border,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.gold
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.ink),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
        linearTrackColor: AppColors.border,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.brand,
          borderRadius: AppRadii.pillBorder,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.brandInkSoft),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: AppColors.inkSoft,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.inkFaint,
        ),
      ),

      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Color(0x33938A78)),
        thickness: WidgetStatePropertyAll(8),
        radius: Radius.circular(4),
      ),
    );
  }
}

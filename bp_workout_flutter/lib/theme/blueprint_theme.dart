import 'package:flutter/material.dart';

import 'blueprint_colors.dart';

ThemeData buildBlueprintTheme() {
  const scheme = ColorScheme.dark(
    surface: BlueprintColors.bg,
    primary: BlueprintColors.purple,
    secondary: BlueprintColors.lavender,
    onSurface: BlueprintColors.cream,
    onPrimary: BlueprintColors.cream,
    error: BlueprintColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: BlueprintColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: BlueprintColors.bg,
      foregroundColor: BlueprintColors.cream,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: BlueprintColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: BlueprintColors.border),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: BlueprintColors.card,
      selectedItemColor: BlueprintColors.purple,
      unselectedItemColor: BlueprintColors.muted,
      type: BottomNavigationBarType.fixed,
    ),
    dividerTheme: const DividerThemeData(color: BlueprintColors.border),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: BlueprintColors.cream),
      bodyMedium: TextStyle(color: BlueprintColors.cream),
      bodySmall: TextStyle(color: BlueprintColors.mutedLight),
      titleLarge: TextStyle(
        color: BlueprintColors.cream,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: BlueprintColors.cream,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

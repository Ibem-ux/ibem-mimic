import 'package:flutter/material.dart';

/// Game theme - dark theme for the social deduction game facade
final ThemeData gameTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0F0F14), // Dark background #0F0F14
  primaryColor: const Color(0xFF7F77DD), // Primary color #7F77DD
  colorScheme: ColorScheme.dark(
    primary: const Color(0xFF7F77DD), // Primary #7F77DD
    secondary: const Color(0xFF1D9E75), // Accent #1D9E75
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 16),
    bodyMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 14),
    bodySmall: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 12),
    titleLarge: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.bold),
    titleSmall: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 16, fontWeight: FontWeight.bold),
  ),
  fontFamily: 'SpaceGrotesk',
);

/// Vault theme - light theme for the encrypted vault
final ThemeData vaultTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: Colors.white, // White background
  colorScheme: ColorScheme.light(
    primary: const Color(0xFF534AB7), // Accent #534AB7
    surface: const Color(0xFFF1EFE8), // Surface #F1EFE8
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16),
    bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14),
    bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12),
    titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold),
    titleSmall: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
  ),
  fontFamily: 'Inter',
);

/// Export both themes for use in their respective modules
/// Game module should only use gameTheme
/// Vault module should only use vaultTheme
/// Never mix these themes between modules as per requirements

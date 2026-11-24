import 'package:flutter/material.dart';

/// MeeD POS colours, matching the kiosk app's palette so the two apps look like one product.
class MeedColors {
  const MeedColors._();

  static const Color brand = Color(0xFF1C7C54);
  static const Color brandDark = Color(0xFF145C3E);
  static const Color accent = Color(0xFFF2A541);
  static const Color danger = Color(0xFFC0392B);
  static const Color surface = Color(0xFFF6F7F5);
  static const Color card = Colors.white;
  static const Color ink = Color(0xFF14211C);
  static const Color inkSoft = Color(0xFF5B6B64);
  static const Color line = Color(0xFFE2E7E4);

  /// Table states on the floor grid.
  static const Color tableFree = Color(0xFFEFF5F2);
  static const Color tableBusy = Color(0xFFFDF2E3);
  static const Color tableMine = Color(0xFFDFF1E7);
  static const Color tableLocked = Color(0xFFF2E6E6);
  static const Color tableDisabled = Color(0xFFECECEC);
}

/// One light theme. The app is a working tool held at arm's length in a dim dining room: large
/// touch targets, strong contrast, no dark variant to go wrong under shop lighting.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MeedColors.brand,
    primary: MeedColors.brand,
    surface: MeedColors.card,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MeedColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: MeedColors.card,
      foregroundColor: MeedColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: MeedColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: MeedColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: MeedColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // 52 high: comfortable for a thumb while carrying plates.
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MeedColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MeedColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MeedColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MeedColors.brand, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MeedColors.ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
    ),
    dividerTheme: const DividerThemeData(color: MeedColors.line, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: MeedColors.inkSoft,
      titleTextStyle: TextStyle(color: MeedColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
      subtitleTextStyle: TextStyle(color: MeedColors.inkSoft, fontSize: 14),
    ),
  );
}

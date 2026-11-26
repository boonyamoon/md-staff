import 'package:flutter/material.dart';

/// MeeD POS colours, matching the kiosk app's palette so the two apps look like one product.
class MeedColors {
  const MeedColors._();

  /// Used until a branch's own `theme_color` is known, and when it has none. Widgets read the
  /// colour in force from `Theme.of(context).colorScheme.primary`, never from here.
  static const Color defaultPrimary = Color(0xFFFF471A);
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
  static const Color tableLocked = Color(0xFFF2E6E6);
  static const Color tableDisabled = Color(0xFFECECEC);

  /// The ring around a table on the floor, by how far along its food is.
  static const Color ringFree = Color(0xFFE1E5EA);
  static const Color ringNotOrdered = Color(0xFF6B7183);
  static const Color ringWaiting = Color(0xFFF2A33C);
  static const Color ringServed = Color(0xFF8BC653);
  static const Color tableText = Color(0xFF5F6676);
}

/// A `#RRGGBB` (or `AARRGGBB`) string as a colour, or null when it is not one.
Color? colorFromHex(String? hex) {
  final cleaned = (hex ?? '').trim().replaceFirst('#', '');
  if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(cleaned)) return null;
  final value = int.parse(cleaned, radix: 16);
  return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
}

/// A branch's `theme_color` as the app's primary: always opaque, and the default when unusable.
Color themeColorFrom(String? hex) =>
    colorFromHex(hex)?.withValues(alpha: 1) ?? MeedColors.defaultPrimary;

/// The shades derived from whatever the primary colour currently is.
extension PrimaryShades on ColorScheme {
  /// For text in the primary hue on a light background.
  Color get primaryStrong => Color.lerp(primary, Colors.black, 0.28)!;

  /// A pale fill: a selected card, a table this handset holds.
  Color get primaryTint => Color.alphaBlend(primary.withValues(alpha: 0.12), MeedColors.card);
}

/// One light theme. The app is a working tool held at arm's length in a dim dining room: large
/// touch targets, strong contrast, no dark variant to go wrong under shop lighting.
ThemeData buildAppTheme([Color primary = MeedColors.defaultPrimary]) {
  // A shop may pick any colour, including a pale one that white text would vanish on.
  final onPrimary = ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
      ? Colors.white
      : MeedColors.ink;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    onPrimary: onPrimary,
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
        borderSide: BorderSide(color: primary, width: 2),
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSwitcher extends ChangeNotifier {
  static final ThemeSwitcher _instance = ThemeSwitcher._internal();
  factory ThemeSwitcher() => _instance;
  ThemeSwitcher._internal();

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode') ?? 'system';

    switch (savedTheme) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    String value;

    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }

    await prefs.setString('theme_mode', value);
  }

  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.light) {
      await setThemeMode(ThemeMode.dark);
    } else {
      await setThemeMode(ThemeMode.light);
    }
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    fontFamily: 'Inter',

    colorScheme: const ColorScheme.light(
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF8B5CF6),
      surface: Colors.white,
      surfaceContainerHighest: Color(0xFFF1F5F9),
      error: Color(0xFFEF4444),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF1E293B),
      onSurfaceVariant: Color(0xFF64748B),
      outline: Color(0xFFE2E8F0),
      tertiary: Color(0xFF10B981),
      tertiaryContainer: Color(0xFFF59E0B),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1E293B),
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Color(0xFF64748B)),
      titleTextStyle: TextStyle(
        color: Color(0xFF1E293B),
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      labelStyle: const TextStyle(color: Color(0xFF64748B)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF3B82F6),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF3B82F6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      displaySmall: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      headlineLarge: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: Color(0xFF64748B),
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF64748B)),
      bodySmall: TextStyle(color: Color(0xFF94A3B8)),
      labelLarge: TextStyle(
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: Color(0xFF64748B),
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(color: Color(0xFF94A3B8)),
    ),

    iconTheme: const IconThemeData(color: Color(0xFF64748B)),

    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(color: Color(0xFF64748B)),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFFE2E8F0),
      thickness: 1,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFF3B82F6),
      unselectedItemColor: Color(0xFF94A3B8),
      elevation: 0,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    fontFamily: 'Inter',

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF60A5FA),
      secondary: Color(0xFFA78BFA),
      surface: Color(0xFF1E293B),
      surfaceContainerHighest: Color(0xFF334155),
      error: Color(0xFFEF4444),
      onPrimary: Color(0xFF0F172A),
      onSecondary: Color(0xFF0F172A),
      onSurface: Color(0xFFF1F5F9),
      onSurfaceVariant: Color(0xFF94A3B8),
      outline: Color(0xFF475569),
      tertiary: Color(0xFF34D399),
      tertiaryContainer: Color(0xFFFBBF24),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Color(0xFFF1F5F9),
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Color(0xFF94A3B8)),
      titleTextStyle: TextStyle(
        color: Color(0xFFF1F5F9),
        fontSize: 20,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1E293B),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF334155),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF475569)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF60A5FA),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF60A5FA),
        side: const BorderSide(color: Color(0xFF475569)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF60A5FA),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      displaySmall: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      headlineLarge: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: Color(0xFFF1F5F9)),
      bodyMedium: TextStyle(color: Color(0xFF94A3B8)),
      bodySmall: TextStyle(color: Color(0xFF64748B)),
      labelLarge: TextStyle(
        color: Color(0xFFF1F5F9),
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: Color(0xFF94A3B8),
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(color: Color(0xFF64748B)),
    ),

    iconTheme: const IconThemeData(color: Color(0xFF94A3B8)),

    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF334155),
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      side: const BorderSide(color: Color(0xFF475569)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFF334155),
      thickness: 1,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E293B),
      selectedItemColor: Color(0xFF60A5FA),
      unselectedItemColor: Color(0xFF64748B),
      elevation: 0,
    ),
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'pages/setup_page.dart';

/// @description Global dictionary storing all application translations.
/// Populated dynamically at startup from assets/translations.json.
Map<String, Map<String, String>> localizedStrings = {};

/// @description Retrieves the localized string for a given key based on the currently active language.
/// @param key The translation key to look up.
/// @returns The translated string, or the key itself if the translation is missing.
String tr(String key) {
  return localizedStrings[ZsebtunApp.languageNotifier.value]?[key] ?? key;
}

/// @description The main entry point of the application. Initializes bindings,
/// loads external translation files, configures global date formatting, and
/// retrieves saved user preferences before launching the app.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final String jsonString = await rootBundle.loadString('assets/translations.json');
  final Map<String, dynamic> rawMap = jsonDecode(jsonString);
  localizedStrings = rawMap.map(
        (lang, map) => MapEntry(lang, Map<String, String>.from(map as Map)),
  );

  await initializeDateFormatting('en_US', null);
  await initializeDateFormatting('hu_HU', null);

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? false;
  final oldRooms = prefs.getBool('oldRooms') ?? true;
  final debugDayOffset = prefs.getInt('debugDayOffset') ?? 0;

  final lightColorInt = prefs.getInt('seedColorLight');
  final darkColorInt = prefs.getInt('seedColorDark');
  final amoledBlack = prefs.getBool('amoledBlack') ?? false;

  String? savedLang = prefs.getString('language');
  if (savedLang == null) {
    final String deviceLang = Platform.localeName.split('_')[0];
    savedLang = (deviceLang == 'hu') ? 'hu' : 'en';
  }

  runApp(ZsebtunApp(
    isDark: isDark,
    initialLang: savedLang,
    oldRooms: oldRooms,
    debugDayOffset: debugDayOffset,
    initialLightColor: lightColorInt != null ? Color(lightColorInt) : const Color(0xFF4F46E5),
    initialDarkColor: darkColorInt != null ? Color(darkColorInt) : const Color(0xFF4F46E5),
    initialAmoled: amoledBlack,
  ));
}

/// @description The root widget of the application. It provides global state management
/// for the theme and language using ValueNotifiers, and dynamically rebuilds
/// the entire MaterialApp when user preferences change.
class ZsebtunApp extends StatelessWidget {
  final bool isDark;
  final String initialLang;
  final bool oldRooms;
  final int debugDayOffset;
  final Color initialLightColor;
  final Color initialDarkColor;
  final bool initialAmoled;

  const ZsebtunApp({
    super.key,
    required this.isDark,
    required this.initialLang,
    required this.oldRooms,
    required this.debugDayOffset,
    required this.initialLightColor,
    required this.initialDarkColor,
    required this.initialAmoled,
  });

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final ValueNotifier<bool> newRoomsNotifier = ValueNotifier(true);
  static late ValueNotifier<String> languageNotifier;
  static final ValueNotifier<int> debugDayOffsetNotifier = ValueNotifier(0);

  static late ValueNotifier<Color> seedColorLightNotifier;
  static late ValueNotifier<Color> seedColorDarkNotifier;
  static late ValueNotifier<bool> amoledBlackNotifier;

  /// @description Formats the currently selected language into a locale string required by the intl package.
  static String get localeString => languageNotifier.value == 'hu' ? 'hu_HU' : 'en_US';

  ThemeData _buildLightTheme(Color seed) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  ThemeData _buildDarkTheme(Color seed, bool isAmoled) {
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    if (isAmoled) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF121212),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF222222),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    newRoomsNotifier.value = oldRooms;
    languageNotifier = ValueNotifier(initialLang);
    debugDayOffsetNotifier.value = debugDayOffset;

    seedColorLightNotifier = ValueNotifier(initialLightColor);
    seedColorDarkNotifier = ValueNotifier(initialDarkColor);
    amoledBlackNotifier = ValueNotifier(initialAmoled);

    return AnimatedBuilder(
      animation: Listenable.merge([
        languageNotifier,
        themeNotifier,
        seedColorLightNotifier,
        seedColorDarkNotifier,
        amoledBlackNotifier,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Zsebtun',
          debugShowCheckedModeBanner: false,
          themeMode: themeNotifier.value,
          theme: _buildLightTheme(seedColorLightNotifier.value),
          darkTheme: _buildDarkTheme(seedColorDarkNotifier.value, amoledBlackNotifier.value),
          home: const SetupPage(),
        );
      },
    );
  }
}
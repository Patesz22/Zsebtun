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
String t(String key) {
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

  String? savedLang = prefs.getString('language');
  if (savedLang == null) {
    final String deviceLang = Platform.localeName.split('_')[0];
    savedLang = (deviceLang == 'hu') ? 'hu' : 'en';
  }

  runApp(ZsebtunApp(isDark: isDark, initialLang: savedLang, oldRooms: oldRooms));
}

/// @description The root widget of the application. It provides global state management
/// for the theme and language using ValueNotifiers, and dynamically rebuilds
/// the entire MaterialApp when user preferences change.
class ZsebtunApp extends StatelessWidget {
  final bool isDark;
  final String initialLang;
  final bool oldRooms;

  const ZsebtunApp({super.key, required this.isDark, required this.initialLang, required this.oldRooms});

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final ValueNotifier<bool> oldRoomsNotifier = ValueNotifier(true);
  static late ValueNotifier<String> languageNotifier;

  /// @description Formats the currently selected language into a locale string required by the intl package.
  static String get localeString => languageNotifier.value == 'hu' ? 'hu_HU' : 'en_US';
  static const Color seedColor = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    oldRoomsNotifier.value = oldRooms;
    languageNotifier = ValueNotifier(initialLang);

    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (_, String currentLang, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, __) {
            return MaterialApp(
              title: 'Zsebtun',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light),
                textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
                appBarTheme: const AppBarTheme(centerTitle: false),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
                textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
                appBarTheme: const AppBarTheme(centerTitle: false),
              ),
              home: const SetupPage(),
            );
          },
        );
      },
    );
  }
}
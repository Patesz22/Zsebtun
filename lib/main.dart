import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// @description The main entry point of the application. Initializes bindings, loads translations,
/// configures date formatting, and retrieves user preferences before running the app.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final String jsonString = await rootBundle.loadString('assets/translations.json');
  final Map<String, dynamic> rawMap = jsonDecode(jsonString);
  localizedStrings = rawMap.map(
        (lang, map) => MapEntry(lang, Map<String, String>.from(map as Map)),
  );

  await initializeDateFormatting('en_US', null);
  await initializeDateFormatting('en_GB', null);
  await initializeDateFormatting('hu_HU', null);

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? false;
  final oldRooms = prefs.getBool('oldRooms') ?? true;
  final debugDayOffset = prefs.getInt('debugDayOffset') ?? 0;

  final lightColorInt = prefs.getInt('seedColorLight');
  final darkColorInt = prefs.getInt('seedColorDark');
  final amoledBlack = prefs.getBool('amoledBlack') ?? false;
  final zhColorInt = prefs.getInt('zhColor');

  final firstDayOfWeek = prefs.getInt('first_day_of_week') ?? 1;
  final use24Hour = prefs.getBool('use_24h_format') ?? true;
  final dateFormatPattern = prefs.getString('date_format_pattern') ?? 'yyyy. MM. dd.';

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
    initialZhColor: zhColorInt != null ? Color(zhColorInt) : const Color(0xFFE11D48),
    initialFirstDayOfWeek: firstDayOfWeek,
    initialUse24Hour: use24Hour,
    initialDateFormat: dateFormatPattern,
  ));
}

/// @description The root widget of the application providing global theme, language, and format management.
class ZsebtunApp extends StatelessWidget {
  final bool isDark;
  final String initialLang;
  final bool oldRooms;
  final int debugDayOffset;
  final Color initialLightColor;
  final Color initialDarkColor;
  final bool initialAmoled;
  final Color initialZhColor;
  final int initialFirstDayOfWeek;
  final bool initialUse24Hour;
  final String initialDateFormat;

  const ZsebtunApp({
    super.key,
    required this.isDark,
    required this.initialLang,
    required this.oldRooms,
    required this.debugDayOffset,
    required this.initialLightColor,
    required this.initialDarkColor,
    required this.initialAmoled,
    required this.initialZhColor,
    required this.initialFirstDayOfWeek,
    required this.initialUse24Hour,
    required this.initialDateFormat,
  });

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final ValueNotifier<bool> newRoomsNotifier = ValueNotifier(true);
  static final ValueNotifier<String> languageNotifier = ValueNotifier('hu');
  static final ValueNotifier<int> debugDayOffsetNotifier = ValueNotifier(0);

  static final ValueNotifier<Color> seedColorLightNotifier = ValueNotifier(const Color(0xFF4F46E5));
  static final ValueNotifier<Color> seedColorDarkNotifier = ValueNotifier(const Color(0xFF4F46E5));
  static final ValueNotifier<bool> amoledBlackNotifier = ValueNotifier(false);
  static final ValueNotifier<Color> zhColorNotifier = ValueNotifier(const Color(0xFFE11D48));

  static final ValueNotifier<int> firstDayOfWeekNotifier = ValueNotifier(1);
  static final ValueNotifier<bool> use24HourFormatNotifier = ValueNotifier(true);
  static final ValueNotifier<String> dateFormatNotifier = ValueNotifier('yyyy. MM. dd.');

  /// @description Returns the locale string identifier for the active language.
  static String get localeString => languageNotifier.value == 'hu' ? 'hu_HU' : 'en_US';

  /// @description Formats a DateTime instance into a localized string using the active date format.
  /// @param date The date to format.
  /// @returns The formatted date string.
  static String formatDate(DateTime date) {
    return DateFormat(dateFormatNotifier.value, localeString).format(date);
  }

  /// @description Formats a TimeOfDay instance into a string using the active 12-hour or 24-hour preference.
  /// @param time The time to format.
  /// @returns The formatted time string.
  static String formatTimeOfDay(TimeOfDay time) {
    final dt = DateTime(2026, 1, 1, time.hour, time.minute);
    final pattern = use24HourFormatNotifier.value ? 'HH:mm' : 'hh:mm a';
    return DateFormat(pattern, localeString).format(dt);
  }

  /// @description Formats a DateTime instance into a time string using the active 12-hour or 24-hour preference.
  /// @param time The timestamp to format.
  /// @returns The formatted time string.
  static String formatTime(DateTime time) {
    final pattern = use24HourFormatNotifier.value ? 'HH:mm' : 'hh:mm a';
    return DateFormat(pattern, localeString).format(time);
  }

  /// @description Resolves the appropriate calendar picker locale according to language and first-day preferences.
  /// @returns The resolved Locale instance.
  static Locale getCalendarPickerLocale() {
    if (languageNotifier.value == 'hu') {
      if (firstDayOfWeekNotifier.value == 1) {
        return const Locale('hu', 'HU');
      }
      return const Locale('en', 'US');
    }
    if (firstDayOfWeekNotifier.value == 1) {
      return const Locale('en', 'GB');
    }
    return const Locale('en', 'US');
  }

  /// @description Persists the chosen first day of the week preference and updates the reactive notifier.
  /// @param day The first day value (1 for Monday, 0 for Sunday).
  static Future<void> setFirstDayOfWeek(int day) async {
    firstDayOfWeekNotifier.value = day;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('first_day_of_week', day);
  }

  /// @description Persists the chosen 24-hour or 12-hour format preference and updates the reactive notifier.
  /// @param is24h True for 24-hour format, false for 12-hour format.
  static Future<void> setUse24HourFormat(bool is24h) async {
    use24HourFormatNotifier.value = is24h;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_24h_format', is24h);
  }

  /// @description Persists the chosen date formatting pattern and updates the reactive notifier.
  /// @param pattern The date pattern string.
  static Future<void> setDateFormat(String pattern) async {
    dateFormatNotifier.value = pattern;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('date_format_pattern', pattern);
  }

  /// @description Constructs the light theme configuration using the provided seed color.
  /// @param seed The seed color for the color scheme.
  /// @returns Configured ThemeData instance.
  ThemeData _buildLightTheme(Color seed) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  /// @description Constructs the dark theme configuration using the seed color and optional AMOLED black background.
  /// @param seed The seed color for the color scheme.
  /// @param isAmoled Whether to use pure black surfaces.
  /// @returns Configured ThemeData instance.
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
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  /// @description Builds the reactive MaterialApp hierarchy listening to all global preference notifiers.
  /// @param context The build context.
  /// @returns The widget tree.
  @override
  Widget build(BuildContext context) {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    newRoomsNotifier.value = oldRooms;
    languageNotifier.value = initialLang;
    debugDayOffsetNotifier.value = debugDayOffset;

    seedColorLightNotifier.value = initialLightColor;
    seedColorDarkNotifier.value = initialDarkColor;
    amoledBlackNotifier.value = initialAmoled;
    zhColorNotifier.value = initialZhColor;

    firstDayOfWeekNotifier.value = initialFirstDayOfWeek;
    use24HourFormatNotifier.value = initialUse24Hour;
    dateFormatNotifier.value = initialDateFormat;

    return AnimatedBuilder(
      animation: Listenable.merge([
        languageNotifier,
        themeNotifier,
        seedColorLightNotifier,
        seedColorDarkNotifier,
        amoledBlackNotifier,
        zhColorNotifier,
        firstDayOfWeekNotifier,
        use24HourFormatNotifier,
        dateFormatNotifier,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Zsebtun',
          debugShowCheckedModeBanner: false,
          themeMode: themeNotifier.value,
          theme: _buildLightTheme(seedColorLightNotifier.value),
          darkTheme: _buildDarkTheme(seedColorDarkNotifier.value, amoledBlackNotifier.value),
          locale: getCalendarPickerLocale(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('hu', 'HU'),
            Locale('en', 'US'),
            Locale('en', 'GB'),
          ],
          home: const SetupPage(),
        );
      },
    );
  }
}
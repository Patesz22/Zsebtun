import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../database/db_helper.dart';
import 'setup_page.dart';

/// @description A dedicated page for user preferences, allowing them to toggle
/// dark mode, change the application language, or log out by clearing their saved Neptun link.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// @description Clears the user's saved ICS link and empties the local database,
  /// then navigates back to the initial setup screen by completely clearing the navigation stack.
  /// @param context The build context used for navigation.
  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ics_link');
    await DatabaseHelper.instance.clearEvents();

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SetupPage()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t('settings'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        children: [
          ValueListenableBuilder<ThemeMode>(
              valueListenable: ZsebtunApp.themeNotifier,
              builder: (context, currentMode, child) {
                final isDark = currentMode == ThemeMode.dark;
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(t('dark_mode'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  value: isDark,
                  activeColor: theme.colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: theme.colorScheme.surfaceContainerLowest,
                  onChanged: (value) async {
                    ZsebtunApp.themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('isDark', value);
                  },
                );
              }
          ),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
              valueListenable: ZsebtunApp.oldRoomsNotifier,
              builder: (context, useNewRooms, child) {
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(t('use_new_rooms'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text(t('use_new_rooms_desc'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.meeting_room_rounded, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  value: useNewRooms,
                  activeColor: theme.colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: theme.colorScheme.surfaceContainerLowest,
                  onChanged: (value) async {
                    ZsebtunApp.oldRoomsNotifier.value = value;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('oldRooms', value);
                  },
                );
              }
          ),
          const SizedBox(height: 12),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: theme.colorScheme.surfaceContainerLowest,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.language, color: theme.colorScheme.onSecondaryContainer),
            ),
            title: Text(t('language'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
            trailing: ValueListenableBuilder<String>(
                valueListenable: ZsebtunApp.languageNotifier,
                builder: (context, currentLang, child) {
                  return DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentLang,
                      dropdownColor: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
                      items: [
                        DropdownMenuItem(value: 'hu', child: Text(t('hungarian'), style: TextStyle(color: theme.colorScheme.onSurface))),
                        DropdownMenuItem(value: 'en', child: Text(t('english'), style: TextStyle(color: theme.colorScheme.onSurface))),
                      ],
                      onChanged: (String? newLang) async {
                        if (newLang != null) {
                          ZsebtunApp.languageNotifier.value = newLang;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('language', newLang);
                        }
                      },
                    ),
                  );
                }
            ),
          ),
          const SizedBox(height: 32),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            leading: Icon(Icons.sync_problem, color: theme.colorScheme.error),
            title: Text(t('change_link'), style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
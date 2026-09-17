import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../database/db_helper.dart';
import 'setup_page.dart';
import '../services/github_update_service.dart';

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
        title: Text(tr('settings'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
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
                  title: Text(tr('dark_mode'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  value: isDark,
                  activeThumbColor: theme.colorScheme.primary,
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
              valueListenable: ZsebtunApp.newRoomsNotifier,
              builder: (context, useNewRooms, child) {
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(tr('use_new_rooms'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('use_new_rooms_desc'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.meeting_room_rounded, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  value: useNewRooms,
                  activeThumbColor: theme.colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: theme.colorScheme.surfaceContainerLowest,
                  onChanged: (value) async {
                    ZsebtunApp.newRoomsNotifier.value = value;
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
            title: Text(tr('language'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
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
                        DropdownMenuItem(value: 'hu', child: Text(tr('hungarian'), style: TextStyle(color: theme.colorScheme.onSurface))),
                        DropdownMenuItem(value: 'en', child: Text(tr('english'), style: TextStyle(color: theme.colorScheme.onSurface))),
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
          const SizedBox(height: 12),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: theme.colorScheme.surfaceContainerLowest,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.system_update_rounded, color: theme.colorScheme.onPrimaryContainer),
            ),
            title: Text(tr('check_updates'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('checking_updates'))));
              GithubUpdateService.checkForUpdates(context, showUpToDateMessage: true);
            },
          ),
          const SizedBox(height: 32),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tileColor: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            leading: Icon(Icons.sync_problem, color: theme.colorScheme.error),
            title: Text(tr('change_link'), style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
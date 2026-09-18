import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  bool _editDarkMode = false;

  final List<Color> _presetColors = [
    const Color(0xFF4F46E5), Colors.deepPurple, Colors.purple, Colors.indigo,
    Colors.blue, Colors.lightBlue, Colors.cyan, Colors.teal,
    Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow,
    Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink,
  ];

  Future<void> _updateColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    if (_editDarkMode) {
      ZsebtunApp.seedColorDarkNotifier.value = color;
      await prefs.setInt('seedColorDark', color.value);
    } else {
      ZsebtunApp.seedColorLightNotifier.value = color;
      await prefs.setInt('seedColorLight', color.value);
    }
  }

  Future<void> _toggleAmoled(bool value) async {
    ZsebtunApp.amoledBlackNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('amoledBlack', value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(tr('appearance'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.light_mode_rounded), label: Text(tr('light_mode') == 'light_mode' ? 'Light Theme' : tr('light_mode'))),
                ButtonSegment(value: true, icon: const Icon(Icons.dark_mode_rounded), label: Text(tr('dark_mode') == 'dark_mode' ? 'Dark Theme' : tr('dark_mode'))),
              ],
              selected: {_editDarkMode},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() => _editDarkMode = newSelection.first);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainer,
                selectedForegroundColor: theme.colorScheme.onPrimary,
                selectedBackgroundColor: theme.colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            _editDarkMode ? tr('edit_dark_color').toUpperCase() : tr('edit_light_color').toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),

          ValueListenableBuilder<Color>(
              valueListenable: _editDarkMode ? ZsebtunApp.seedColorDarkNotifier : ZsebtunApp.seedColorLightNotifier,
              builder: (context, currentColor, _) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _presetColors.length,
                  itemBuilder: (context, index) {
                    final color = _presetColors[index];
                    final isSelected = currentColor.value == color.value;

                    return GestureDetector(
                      onTap: () => _updateColor(color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: theme.colorScheme.onSurface, width: 3) : null,
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 28)
                            : null,
                      ),
                    );
                  },
                );
              }
          ),

          const SizedBox(height: 32),

          Text(
            'DISPLAY',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),

          ValueListenableBuilder<bool>(
              valueListenable: ZsebtunApp.amoledBlackNotifier,
              builder: (context, isAmoled, _) {
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: theme.colorScheme.surfaceContainerLowest,
                  title: Text(tr('amoled_black'), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('amoled_desc'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.dark_mode_rounded, color: Colors.white),
                  ),
                  value: isAmoled,
                  activeColor: theme.colorScheme.primary,
                  onChanged: _toggleAmoled,
                );
              }
          ),
        ],
      ),
    );
  }
}
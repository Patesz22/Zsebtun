import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'dashboard_page.dart';

/// @description The initial routing and onboarding page of the application.
/// It checks if the user has already saved a calendar link; if so, it silently
/// redirects to the Dashboard. Otherwise, it presents the setup form.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final TextEditingController _linkController = TextEditingController();
  bool _isLoading = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLink();
  }

  /// @description Verifies if a Neptun ICS link is already saved in local storage.
  /// If a link exists, it bypasses the setup screen and routes directly to the Dashboard.
  Future<void> _checkExistingLink() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString('ics_link');

    if (link != null && link.isNotEmpty) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
      }
    } else {
      setState(() {
        _isChecking = false;
      });
    }
  }

  /// @description Validates the user's input, saves the link to local storage if valid,
  /// and navigates the user to their newly populated Dashboard.
  Future<void> _saveAndContinue() async {
    final link = _linkController.text.trim();
    if (link.isEmpty || !link.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('invalid_link')), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ics_link', link);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isChecking) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Icon(Icons.calendar_today_rounded, size: 80, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  t('setup_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t('setup_desc'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _linkController,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: t('link_label'),
                    labelStyle: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    hintText: 'https://neptun...',
                    hintStyle: TextStyle(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.link_rounded, color: Colors.grey),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLoading ? null : _saveAndContinue,
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                      : Text(
                      t('sync_button'),
                      style: TextStyle(
                          fontSize: 18,
                          color: theme.colorScheme.onPrimary
                      )
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
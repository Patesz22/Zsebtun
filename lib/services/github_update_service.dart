import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

/// @description Service to check GitHub for new app releases and redirect the user.
/// Complies with Android store policies by avoiding direct APK background downloads.
class GithubUpdateService {
  static const String _repoOwner = 'patesz22';
  static const String _repoName = 'zsebtun';
  static const String _apiUrl = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _releaseUrl = 'https://github.com/$_repoOwner/$_repoName/releases/latest';

  /// @description Queries the GitHub API to compare the installed version against the latest tag.
  /// @param context The BuildContext used for showing dialogs/snackbars.
  /// @param showUpToDateMessage If true, displays a snackbar when no update is needed (for manual checks).
  static Future<void> checkForUpdates(BuildContext context, {bool showUpToDateMessage = false}) async {
    try {
      final response = await http.get(Uri.parse(_apiUrl));
      if (response.statusCode != 200) throw Exception('Failed to fetch release');

      final data = jsonDecode(response.body);
      final latestTag = data['tag_name'] as String;
      final latestVersion = latestTag.replaceAll('v', '');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('DEBUG: Local App Version is: $currentVersion');
      debugPrint('DEBUG: GitHub Latest Version is: $latestVersion');

      if (_isNewerVersion(currentVersion, latestVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion);
        }
      } else if (showUpToDateMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('up_to_date'))));
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      if (showUpToDateMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('update_error'))));
      }
    }
  }

  /// @description Safely compares two semantic version strings, ignoring 'v' prefixes and build metadata.
  /// @param current The locally installed version (e.g., '2.0.0+1').
  /// @param latest The version fetched from GitHub (e.g., 'v0.1.1').
  /// @returns True if the GitHub version is mathematically higher.
  static bool _isNewerVersion(String current, String latest) {
    try {
      String cleanCurrent = current.toLowerCase().replaceAll('v', '');
      String cleanLatest = latest.toLowerCase().replaceAll('v', '');

      cleanCurrent = cleanCurrent.split('+')[0].split('-')[0];
      cleanLatest = cleanLatest.split('+')[0].split('-')[0];

      final currParts = cleanCurrent.split('.').map(int.parse).toList();
      final latParts = cleanLatest.split('.').map(int.parse).toList();

      final maxLength = currParts.length > latParts.length
          ? currParts.length
          : latParts.length;

      for (int i = 0; i < maxLength; i++) {
        // Pad missing sub-versions with 0 (so 1.0 == 1.0.0)
        final currVal = i < currParts.length ? currParts[i] : 0;
        final latVal = i < latParts.length ? latParts[i] : 0;

        if (latVal > currVal) return true;
        if (latVal < currVal) return false;
      }

      return false;
    } catch (e) {
      debugPrint('Version parsing error: $e');
      return false;
    }
  }

  /// @description Displays an alert dialog prompting the user to view the update.
  /// @param context The BuildContext.
  /// @param version The latest version string to display.
  static void _showUpdateDialog(BuildContext context, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr('update_available')),
        content: Text(tr('update_desc').replaceAll('{v}', version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('later')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _launchGitHub(context);
            },
            child: Text(tr('update_now')),
          ),
        ],
      ),
    );
  }

  /// @description Launches the default system browser to the GitHub latest release page.
  /// @param context The BuildContext used to show the loading snackbar.
  static Future<void> _launchGitHub(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('downloading'))));

    final Uri url = Uri.parse(_releaseUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }
}
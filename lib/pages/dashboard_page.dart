import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../database/db_helper.dart';
import '../services/ics_parser_service.dart';
import 'calendar_page.dart';
import 'settings_page.dart';
import '../services/room_formatter_service.dart';

/// @description The main landing page of the application displaying current day statistics,
/// a dynamic greeting, and an actively counting down hero card for the next upcoming class.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _todayEvents = [];
  Map<String, dynamic>? _nextEvent;
  int _remainingClasses = 0;
  bool _isLoading = true;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();

    // Update the UI every minute to keep the "starts in X mins" accurate
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _calculateNextClass();
    });
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  /// @description Initializes the dashboard by first loading offline data instantly,
  /// then triggering a background network sync to check for schedule changes.
  Future<void> _initializeDashboard() async {
    await _loadFromDatabase();
    await _fetchAndSyncCalendar();
  }

  /// @description Fetches all events from the local SQLite database and filters them
  /// to populate the current day's schedule.
  Future<void> _loadFromDatabase() async {
    _allEvents = await DatabaseHelper.instance.getEvents();
    final now = DateTime.now();

    _todayEvents = _allEvents.where((event) {
      final dt = event['dtstart'] as DateTime;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();

    _calculateNextClass();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// @description Downloads the latest .ics file from the saved Neptun URL, parses it,
  /// and updates the local database silently. Reloads the UI if new data arrives.
  Future<void> _fetchAndSyncCalendar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final link = prefs.getString('ics_link');
      if (link == null) return;

      final response = await http.get(Uri.parse(link));
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final formattedEvents = IcsParserService.parseNeptunIcs(decodedBody);

        await DatabaseHelper.instance.saveEvents(formattedEvents);

        if (mounted) {
          await _loadFromDatabase();
        }
      }
    } catch (e) {
      debugPrint('Dashboard Sync Error: $e');
    }
  }

  /// @description Iterates through today's classes to find the next upcoming event
  /// based on the current device time and calculates the remaining class count.
  void _calculateNextClass() {
    final now = DateTime.now();
    _nextEvent = null;
    int remainingCount = 0;

    for (var event in _todayEvents) {
      final startTime = event['dtstart'] as DateTime;
      final endTime = event['dtend'] as DateTime;

      if (endTime.isAfter(now)) {
        if (_nextEvent == null && startTime.isAfter(now)) {
          _nextEvent = event;
        }
        remainingCount++;
      }
    }

    setState(() {
      _remainingClasses = remainingCount;
    });
  }

  /// @description Generates a time-appropriate greeting (morning, afternoon, evening).
  /// @returns A localized greeting string.
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return t('greeting_morning');
    if (hour < 18) return t('greeting_afternoon');
    return t('greeting_evening');
  }

  /// @description Calculates the formatted time remaining until a target DateTime.
  /// @param target The future DateTime to compare against.
  /// @returns A localized string representing the remaining hours and minutes.
  String _getTimeUntil(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return t('now');

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours > 0) {
      return '$hours${t('hrs')} $minutes${t('mins')}';
    }
    return '$minutes${t('mins')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t('dashboard'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : RefreshIndicator(
        onRefresh: () async {
          setState(() => _isLoading = true);
          await _fetchAndSyncCalendar();
        },
        color: theme.colorScheme.primary,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _getGreeting(),
              style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat(t('date_format'), ZsebtunApp.localeString).format(now),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 32),

            Text(
              t('next_class').toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
                valueListenable: ZsebtunApp.oldRoomsNotifier,
                builder: (context, useNewRooms, child) {
                  return _buildNextClassCard(theme, isDark, useNewRooms);
                }
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    theme: theme,
                    title: t('classes_today'),
                    value: _todayEvents.length.toString(),
                    icon: Icons.calendar_today_rounded,
                    color: theme.colorScheme.secondaryContainer,
                    onColor: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatBox(
                    theme: theme,
                    title: t('remaining'),
                    value: _remainingClasses.toString(),
                    icon: Icons.pending_actions_rounded,
                    color: theme.colorScheme.tertiaryContainer,
                    onColor: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            InkWell(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CalendarPage(preloadedEvents: _allEvents))
              ),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.date_range_rounded, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('open_calendar'),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('ready_for_day'),
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// @description Builds the hero card displaying information about the user's next immediate class.
  /// @param theme The current ThemeData context.
  /// @param isDark Boolean indicating if dark mode is active to adjust shadows.
  /// @param useNewRooms Boolean indicating if the user prefers raw unformatted room names.
  /// @returns A styled Container widget.
  Widget _buildNextClassCard(ThemeData theme, bool isDark, bool useNewRooms) {
    if (_nextEvent == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(Icons.done_all_rounded, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              t('no_more_classes'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final startTime = _nextEvent!['dtstart'] as DateTime;
    final className = _nextEvent!['className'] ?? t('unknown_class');
    final roomsList = _nextEvent!['rooms'] as List<dynamic>? ?? [];

    final location = roomsList.isNotEmpty
        ? roomsList.map((r) => useNewRooms ? r['raw'].toString() : RoomFormatterService.formatRoomName(r['raw'].toString())).join(', ')
        : t('unknown_room');

    final classType = _nextEvent!['classType']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 6),
                    Text(
                      '${t('starts_in')} ${_getTimeUntil(startTime)}',
                      style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat('HH:mm').format(startTime),
                style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (classType.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  classType,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary, letterSpacing: 0.5)
              ),
            ),
          Text(
            className,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary, height: 1.2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: theme.colorScheme.onPrimary.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onPrimary.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// @description Builds a square statistics box used for displaying daily metrics.
  /// @param theme The current ThemeData context.
  /// @param title The label for the statistic.
  /// @param value The numerical value to display.
  /// @param icon The IconData to display.
  /// @param color The background color of the box.
  /// @param onColor The text and icon color, ensuring high contrast against the background.
  /// @returns A styled Container widget.
  Widget _buildStatBox({
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color onColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: onColor),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 13, color: onColor.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
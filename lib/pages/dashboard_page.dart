import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zsebtun/database/db_helper.dart';
import 'package:zsebtun/main.dart';
import 'package:zsebtun/pages/calendar_page.dart';
import 'package:zsebtun/pages/settings_page.dart';
import 'package:zsebtun/pages/zh_list_page.dart';
import 'package:zsebtun/services/github_update_service.dart';
import 'package:zsebtun/services/ics_parser_service.dart';
import 'package:zsebtun/services/room_formatter_service.dart';

/// @description The main landing page of the application displaying current day statistics,
/// a dynamic greeting, and an actively counting down hero card for the next upcoming class or exam.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  /// @description Creates the state instance for DashboardPage.
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _todayEvents = [];

  Map<String, dynamic>? _currentClass;
  Map<String, dynamic>? _nextClass;

  int _totalClasses = 0;
  int _finishedClasses = 0;
  bool _isLoading = true;
  Timer? _minuteTimer;

  /// @description Provides the simulated current time by applying the debug day offset.
  DateTime get _simulatedNow => DateTime.now().add(Duration(days: ZsebtunApp.debugDayOffsetNotifier.value));

  /// @description Initializes timers, update checks, and listeners for debug offset changes.
  @override
  void initState() {
    super.initState();
    _initializeDashboard();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GithubUpdateService.checkForUpdates(context);
    });

    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _calculateClasses();
    });

    ZsebtunApp.debugDayOffsetNotifier.addListener(_onDebugOffsetChanged);
  }

  /// @description Cancels periodic timers and unregisters debug offset change listeners.
  @override
  void dispose() {
    _minuteTimer?.cancel();
    ZsebtunApp.debugDayOffsetNotifier.removeListener(_onDebugOffsetChanged);
    super.dispose();
  }

  /// @description Handles simulated debug day offset modifications by reloading today's classes.
  void _onDebugOffsetChanged() {
    if (mounted) {
      setState(() => _isLoading = true);
      _loadFromDatabase();
    }
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
    final now = _simulatedNow;

    _todayEvents = _allEvents.where((event) {
      final dt = event['dtstart'] as DateTime;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();

    _calculateClasses();

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

  /// @description Evaluates today's classes to identify the currently running class,
  /// the next upcoming class, and tallies finished vs. total classes.
  void _calculateClasses() {
    final now = _simulatedNow;
    _currentClass = null;
    _nextClass = null;
    _finishedClasses = 0;
    _totalClasses = _todayEvents.length;

    for (final event in _todayEvents) {
      final startTime = event['dtstart'] as DateTime;
      final endTime = event['dtend'] as DateTime;

      if (now.isAfter(endTime)) {
        _finishedClasses++;
      } else if (now.isAfter(startTime) && now.isBefore(endTime)) {
        _currentClass = event;
      } else if (now.isBefore(startTime) && _nextClass == null) {
        _nextClass = event;
      }
    }

    setState(() {});
  }

  /// @description Generates a time-appropriate greeting (morning, afternoon, evening).
  String _getGreeting() {
    final hour = _simulatedNow.hour;
    if (hour < 12) return tr('greeting_morning');
    if (hour < 18) return tr('greeting_afternoon');
    return tr('greeting_evening');
  }

  /// @description Calculates the formatted time remaining until a target DateTime.
  /// @param target The future event start timestamp.
  /// @returns Human-readable string representing remaining time.
  String _getTimeUntil(DateTime target) {
    final diff = target.difference(_simulatedNow);
    if (diff.isNegative) return tr('now');

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours > 0) {
      return '$hours${tr('hrs')} $minutes${tr('mins')}';
    }
    return '$minutes${tr('mins')}';
  }

  /// @description Displays a bottom sheet showing all classes and exams scheduled for today.
  /// @param theme The current application ThemeData.
  /// @param isDark Whether dark mode is currently active.
  /// @param useNewRooms Whether to format rooms with new room naming syntax.
  void _showTodayClassesBottomSheet(ThemeData theme, bool isDark, bool useNewRooms) {
    final zhColor = ZsebtunApp.zhColorNotifier.value;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      tr('todays_classes_list'),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              if (_todayEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Text(tr('no_more_classes'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
                    itemCount: _todayEvents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final event = _todayEvents[index];
                      final startTime = event['dtstart'] as DateTime;
                      final endTime = event['dtend'] as DateTime;
                      final className = event['className']?.toString() ?? tr('unknown_class');
                      final roomsList = (event['rooms'] as List<dynamic>?) ?? <dynamic>[];

                      final location = roomsList.isNotEmpty
                          ? roomsList.map((r) {
                        final raw = r is Map ? (r['raw']?.toString() ?? '') : r.toString();
                        return useNewRooms ? raw : RoomFormatterService.formatRoomName(raw);
                      }).join(', ')
                          : tr('unknown_room');

                      final isFinished = _simulatedNow.isAfter(endTime);
                      final isRunning = _simulatedNow.isAfter(startTime) && _simulatedNow.isBefore(endTime);
                      final isZh = event['isZh'] == 1 || event['classType'] == 'ZH';

                      final tileBorderColor = isRunning
                          ? Colors.green
                          : (isZh ? zhColor.withValues(alpha: 0.5) : null);

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isRunning
                              ? Colors.green.withValues(alpha: 0.15)
                              : (isZh ? zhColor.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainer),
                          borderRadius: BorderRadius.circular(16),
                          border: tileBorderColor != null ? Border.all(color: tileBorderColor, width: isZh ? 1.5 : 1.0) : null,
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ZsebtunApp.formatTime(startTime),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isFinished
                                        ? theme.colorScheme.onSurfaceVariant
                                        : (isZh ? zhColor : theme.colorScheme.onSurface),
                                  ),
                                ),
                                Text(
                                  ZsebtunApp.formatTime(endTime),
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isZh) ...[
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: zhColor.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'ZH',
                                            style: TextStyle(color: zhColor, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          className,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isFinished
                                                ? theme.colorScheme.onSurfaceVariant
                                                : (isRunning ? Colors.green : (isZh ? zhColor : theme.colorScheme.onSurface)),
                                            decoration: isFinished ? TextDecoration.lineThrough : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          location,
                                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isFinished)
                              Icon(Icons.check_circle_rounded, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5))
                            else if (isRunning)
                              const Icon(Icons.play_circle_fill_rounded, color: Colors.green)
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// @description Builds the scaffold containing navigation bars and switching stacks.
  /// @param context The build context.
  /// @returns The main dashboard scaffold.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _selectedIndex == 0
          ? AppBar(
        title: Text(tr('dashboard'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardContent(theme, isDark),
          CalendarPage(preloadedEvents: _allEvents),
          const ZhListPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 0 || index == 1) {
            _loadFromDatabase();
          }
        },
        backgroundColor: theme.colorScheme.surfaceContainer,
        indicatorColor: theme.colorScheme.primaryContainer,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded, color: theme.colorScheme.onPrimaryContainer),
            label: tr('dashboard'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.onPrimaryContainer),
            label: tr('title'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded, color: theme.colorScheme.onPrimaryContainer),
            label: tr('zh_list'),
          ),
        ],
      ),
    );
  }

  /// @description Renders the dashboard list view containing the hero card and stat boxes.
  /// @param theme Active application theme data.
  /// @param isDark Whether dark theme is enabled.
  /// @returns Refreshable dashboard scroll view.
  Widget _buildDashboardContent(ThemeData theme, bool isDark) {
    final now = _simulatedNow;
    final weekday = DateFormat('EEEE', ZsebtunApp.localeString).format(now);

    return RefreshIndicator(
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
            '${ZsebtunApp.formatDate(now)} ($weekday)',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
          ),

          if (ZsebtunApp.debugDayOffsetNotifier.value != 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report_rounded, size: 16, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Debug offset active: ${ZsebtunApp.debugDayOffsetNotifier.value} days',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 32),

          Text(
            tr('next_class').toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: ZsebtunApp.newRoomsNotifier,
            builder: (context, useNewRooms, child) {
              return _buildHeroCard(theme, isDark, useNewRooms);
            },
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: ZsebtunApp.newRoomsNotifier,
                  builder: (context, useNewRooms, child) {
                    return _buildStatBox(
                      theme: theme,
                      title: tr('classes_today'),
                      value: '$_finishedClasses / $_totalClasses',
                      icon: Icons.checklist_rtl_rounded,
                      color: theme.colorScheme.secondaryContainer,
                      onColor: theme.colorScheme.onSecondaryContainer,
                      onTap: () => _showTodayClassesBottomSheet(theme, isDark, useNewRooms),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRightStatBox(theme, isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// @description Builds the hero card displaying either the currently running class,
  /// an upcoming midterm with the custom ZH color, or the next immediate class.
  /// @param theme The current application theme.
  /// @param isDark Whether dark mode is enabled.
  /// @param useNewRooms Whether to format rooms with new room naming syntax.
  /// @returns Widget card representing the active or upcoming scheduled item.
  Widget _buildHeroCard(ThemeData theme, bool isDark, bool useNewRooms) {
    final isRunning = _currentClass != null;
    final heroEvent = _currentClass ?? _nextClass;

    if (heroEvent == null) {
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
              tr('no_more_classes'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final startTime = heroEvent['dtstart'] as DateTime;
    final endTime = heroEvent['dtend'] as DateTime;
    final className = heroEvent['className']?.toString() ?? tr('unknown_class');
    final roomsList = (heroEvent['rooms'] as List<dynamic>?) ?? <dynamic>[];

    final location = roomsList.isNotEmpty
        ? roomsList.map((r) {
      final raw = r is Map ? (r['raw']?.toString() ?? '') : r.toString();
      return useNewRooms ? raw : RoomFormatterService.formatRoomName(raw);
    }).join(', ')
        : tr('unknown_room');

    final classType = heroEvent['classType']?.toString() ?? '';
    final isZh = heroEvent['isZh'] == 1 || classType == 'ZH';
    final zhColor = ZsebtunApp.zhColorNotifier.value;

    final gradientColors = isRunning
        ? [Colors.green.shade600, Colors.green.shade400]
        : (isZh
        ? [zhColor.withValues(alpha: 0.85), zhColor.withValues(alpha: 0.65)]
        : [
      theme.colorScheme.primary.withValues(alpha: 0.75),
      theme.colorScheme.primary.withValues(alpha: 0.55),
    ]);

    final shadowColor = isRunning
        ? Colors.green
        : (isZh ? zhColor.withValues(alpha: 0.5) : theme.colorScheme.primary.withValues(alpha: 0.5));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: isDark ? 0.2 : 0.4),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isRunning ? Icons.play_arrow_rounded : Icons.timer_outlined, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? 'Most!' : '${tr('starts_in')} ${_getTimeUntil(startTime)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                '${ZsebtunApp.formatTime(startTime)} - ${ZsebtunApp.formatTime(endTime)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (classType.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                classType,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
              ),
            ),
          Text(
            className,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location,
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
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

  /// @description Builds the right stat box tracking the next immediate scheduled item.
  /// @param theme Active application theme data.
  /// @param isDark Whether dark theme is enabled.
  /// @returns Widget representing next class summary.
  Widget _buildRightStatBox(ThemeData theme, bool isDark) {
    if (_nextClass == null) {
      return _buildStatBox(
        theme: theme,
        title: tr('no_more_classes'),
        value: '-',
        icon: Icons.fast_forward_rounded,
        color: theme.colorScheme.tertiaryContainer,
        onColor: theme.colorScheme.onTertiaryContainer,
      );
    }

    final startTime = _nextClass!['dtstart'] as DateTime;
    final className = _nextClass!['className']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fast_forward_rounded, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(height: 16),
          Text(
            ZsebtunApp.formatTime(startTime),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.colorScheme.onTertiaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            className,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onTertiaryContainer.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// @description Builds a square statistics box used for displaying daily metrics.
  /// @param theme Active application theme data.
  /// @param title Metric label string.
  /// @param value Big metric value string.
  /// @param icon Leading icon data.
  /// @param color Container background color.
  /// @param onColor Foreground content color.
  /// @param onTap Optional click event callback.
  /// @returns Reusable stat box widget.
  Widget _buildStatBox({
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color onColor,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: onColor),
              const SizedBox(height: 16),
              Text(
                value,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(fontSize: 13, color: onColor.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

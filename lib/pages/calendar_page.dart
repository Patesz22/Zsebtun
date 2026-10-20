import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:zsebtun/database/db_helper.dart';
import 'package:zsebtun/main.dart';
import 'package:zsebtun/pages/settings_page.dart';
import 'package:zsebtun/pages/setup_page.dart';
import 'package:zsebtun/pages/zh_add_edit_page.dart';
import 'package:zsebtun/services/ics_parser_service.dart';
import 'package:zsebtun/services/room_formatter_service.dart';

/// @description The full schedule view that allows users to navigate through their
/// classes and exams using a monthly, weekly, or daily view.
class CalendarPage extends StatefulWidget {

  const CalendarPage({super.key, this.preloadedEvents});
  final List<Map<String, dynamic>>? preloadedEvents;

  /// @description Creates the mutable state object for CalendarPage.
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.week;
  String _selectedView = 'weekly';
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<Map<String, dynamic>>> _groupedEvents = {};
  List<String> _preloadedSubjects = [];
  late bool _isLoading;

  /// @description Initializes calendar state, date selection, and triggers offline/remote event loading.
  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;

    if (widget.preloadedEvents != null && widget.preloadedEvents!.isNotEmpty) {
      _isLoading = false;
      _groupEventsByDate(widget.preloadedEvents!);
      _loadSubjectsOnly();
    } else {
      _isLoading = true;
      _loadOfflineEvents();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _fetchCalendar();
      });
    });
  }

  /// @description Asynchronously loads semester subject names for quick auto-fill when editing exams.
  Future<void> _loadSubjectsOnly() async {
    try {
      final subjects = await DatabaseHelper.instance.getCurrentSemesterSubjects();
      if (mounted) {
        setState(() {
          _preloadedSubjects = subjects;
        });
      }
    } catch (_) {}
  }

  /// @description Retrieves saved classes and exams from the local SQLite database.
  Future<void> _loadOfflineEvents() async {
    final offlineEvents = await DatabaseHelper.instance.getEvents();
    final subjects = await DatabaseHelper.instance.getCurrentSemesterSubjects();
    if (offlineEvents.isNotEmpty && mounted) {
      _groupEventsByDate(offlineEvents);
      setState(() {
        _preloadedSubjects = subjects;
        _isLoading = false;
      });
    }
  }

  /// @description Fetches the latest calendar data from the saved Neptun URL.
  Future<void> _fetchCalendar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final link = prefs.getString('ics_link');
      if (link == null) {
        _logout();
        return;
      }

      final response = await http.get(Uri.parse(link));
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        await _parseICS(decodedBody);
      }
    } catch (e) {
      debugPrint('Szinkronizációs hiba: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// @description Parses downloaded ICS data, saves classes without deleting manual ZHs, and refreshes the UI.
  /// @param icsData The raw multi-line string content of the .ics file.
  Future<void> _parseICS(String icsData) async {
    final formattedEvents = IcsParserService.parseNeptunIcs(icsData);
    await DatabaseHelper.instance.saveEvents(formattedEvents);

    final allEvents = await DatabaseHelper.instance.getEvents();
    final subjects = await DatabaseHelper.instance.getCurrentSemesterSubjects();

    if (mounted) {
      _groupEventsByDate(allEvents);
      setState(() {
        _preloadedSubjects = subjects;
        _isLoading = false;
      });
    }
  }

  /// @description Groups a flat list of events into a Map indexed by date for TableCalendar lookups.
  /// @param flatEvents A list of un-grouped event maps.
  void _groupEventsByDate(List<Map<String, dynamic>> flatEvents) {
    final newGroups = <DateTime, List<Map<String, dynamic>>>{};
    for (final event in flatEvents) {
      final date = event['dtstart'] as DateTime;
      final dateKey = DateTime(date.year, date.month, date.day);

      if (newGroups[dateKey] == null) {
        newGroups[dateKey] = [];
      }
      newGroups[dateKey]!.add(event);
    }
    _groupedEvents = newGroups;
  }

  /// @description Helper function for TableCalendar to load markers under specific dates.
  /// @param day The specific date to look up events for.
  /// @returns A list of events occurring on that day.
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _groupedEvents[normalizedDay] ?? <Map<String, dynamic>>[];
  }

  /// @description Handles the calendar view format change (Daily, Weekly, Monthly).
  /// @param newValue The selected view string from the dropdown.
  void _onViewChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedView = newValue;
        if (newValue == 'monthly') _calendarFormat = CalendarFormat.month;
        if (newValue == 'weekly') _calendarFormat = CalendarFormat.week;
      });
    }
  }

  /// @description Logs the user out by clearing the saved ICS link and emptying the database.
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ics_link');
    await DatabaseHelper.instance.clearEvents();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (context) => const SetupPage()),
            (route) => false,
      );
    }
  }

  /// @description Opens the editor for a manual ZH entry and updates the calendar on save.
  /// @param context The build context used for navigation.
  /// @param event The map representing the exam entry.
  Future<void> _editZhEvent(BuildContext context, Map<String, dynamic> event) async {
    Navigator.pop(context);
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ZhAddEditPage(
          existingEvent: event,
          preloadedSubjects: _preloadedSubjects,
        ),
      ),
    );
    if (changed == true) {
      await _loadOfflineEvents();
    }
  }

  /// @description Displays a bottom sheet modal containing full details of a clicked event or exam.
  /// @param context The build context for the modal.
  /// @param event The data map representing the clicked class or exam.
  void _showEventDetails(BuildContext context, Map<String, dynamic> event) {
    final theme = Theme.of(context);
    final dtStart = event['dtstart'] as DateTime;
    final dtEnd = event['dtend'] as DateTime;

    final startTime = ZsebtunApp.formatTime(dtStart);
    final endTime = ZsebtunApp.formatTime(dtEnd);
    final date = '${ZsebtunApp.formatDate(dtStart)} (${DateFormat('EEEE', ZsebtunApp.localeString).format(dtStart)})';

    final isZh = event['isZh'] == 1 || event['classType'] == 'ZH';
    final defaultZhColor = ZsebtunApp.zhColorNotifier.value;
    final eventColor = isZh
        ? (event['color'] != null ? Color(event['color'] as int) : defaultZhColor)
        : theme.colorScheme.primary;

    final className = event['className']?.toString() ?? tr('unknown_class');
    final classType = event['classType']?.toString() ?? '';
    final eventType = event['eventType']?.toString() ?? '';
    final roomsList = (event['rooms'] as List<dynamic>?) ?? <dynamic>[];
    final teachers = (event['teachers'] as List<dynamic>?) ?? <dynamic>[];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<bool>(
              valueListenable: ZsebtunApp.newRoomsNotifier,
              builder: (context, useNewRooms, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            className,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isZh)
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: eventColor),
                            tooltip: tr('edit_zh'),
                            onPressed: () => _editZhEvent(context, event),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isZh)
                          Chip(
                            label: Text(eventType.isNotEmpty ? eventType : 'ZH'),
                            backgroundColor: eventColor.withValues(alpha: 0.18),
                            labelStyle: TextStyle(color: eventColor, fontWeight: FontWeight.bold, fontSize: 12),
                            side: BorderSide(color: eventColor.withValues(alpha: 0.4)),
                          )
                        else ...[
                          if (classType.isNotEmpty)
                            Chip(
                              label: Text(classType),
                              backgroundColor: theme.colorScheme.primaryContainer,
                              labelStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12),
                              side: BorderSide.none,
                            ),
                          if (eventType.isNotEmpty)
                            Chip(
                              label: Text(eventType),
                              backgroundColor: theme.colorScheme.secondaryContainer,
                              labelStyle: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold, fontSize: 12),
                              side: BorderSide.none,
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(theme, Icons.access_time_rounded, '$date\n$startTime - $endTime'),
                    const SizedBox(height: 16),
                    if (roomsList.isNotEmpty)
                      _buildDetailRow(
                        theme,
                        Icons.location_on_rounded,
                        roomsList.map((r) {
                          final raw = r is Map ? (r['raw']?.toString() ?? '') : r.toString();
                          final formatted = useNewRooms ? raw : RoomFormatterService.formatRoomName(raw);
                          final floor = (r is Map && r['floor'] != null && r['floor'].toString().isNotEmpty)
                              ? ' (${r['floor']})'
                              : '';
                          return '$formatted$floor';
                        }).join('\n'),
                      )
                    else
                      _buildDetailRow(theme, Icons.location_off_rounded, tr('unknown_room')),
                    if (teachers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        theme,
                        Icons.person_rounded,
                        teachers.map((t) => t.toString()).join('\n'),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// @description A reusable row widget for displaying an icon alongside text in the event details modal.
  /// @param theme The active ThemeData.
  /// @param icon The IconData to display.
  /// @param text The string text to display next to the icon.
  /// @returns A configured Row widget.
  Widget _buildDetailRow(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// @description Builds the entire calendar page widget tree including calendar picker and event cards.
  /// @param context The build context.
  /// @returns The complete scaffold widget.
  @override
  Widget build(BuildContext context) {
    final selectedDayEvents = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : <Map<String, dynamic>>[];
    final theme = Theme.of(context);
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(tr('title'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedView,
                icon: Icon(Icons.expand_more_rounded, color: theme.colorScheme.primary),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                dropdownColor: theme.colorScheme.surfaceContainer,
                elevation: 3,
                borderRadius: BorderRadius.circular(16),
                onChanged: _onViewChanged,
                items: ['daily', 'weekly', 'monthly'].map((value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(tr(value), style: TextStyle(color: theme.colorScheme.onSurface)),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            tooltip: tr('settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading && _groupedEvents.isEmpty
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : Column(
        children: [
          if (_selectedView != 'daily')
            ValueListenableBuilder<int>(
              valueListenable: ZsebtunApp.firstDayOfWeekNotifier,
              builder: (context, firstDayOfWeek, _) {
                return ColoredBox(
                  color: theme.colorScheme.surface,
                  child: TableCalendar<Map<String, dynamic>>(
                    locale: ZsebtunApp.localeString,
                    firstDay: DateTime(currentYear - 3),
                    lastDay: DateTime(currentYear + 3, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    startingDayOfWeek: firstDayOfWeek == 1
                        ? StartingDayOfWeek.monday
                        : StartingDayOfWeek.sunday,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    eventLoader: _getEventsForDay,
                    calendarBuilders: CalendarBuilders<Map<String, dynamic>>(
                      markerBuilder: (context, date, events) {
                        if (events.isEmpty) return null;
                        final maxVisibleDots = events.length > 5 ? 5 : events.length;
                        final visibleEvents = events.take(maxVisibleDots).toList();

                        return Positioned(
                          bottom: 2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: visibleEvents.map((eventMap) {
                              final isZh = eventMap['isZh'] == 1 || eventMap['classType'] == 'ZH';
                              final dotColor = isZh
                                  ? (eventMap['color'] != null
                                  ? Color(eventMap['color'] as int)
                                  : ZsebtunApp.zhColorNotifier.value)
                                  : theme.colorScheme.tertiary;

                              return Container(
                                width: 4.5,
                                height: 4.5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      leftChevronIcon: Icon(Icons.chevron_left, color: theme.colorScheme.onSurface),
                      rightChevronIcon: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                      weekendStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle: TextStyle(color: theme.colorScheme.onSurface),
                      weekendTextStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                      outsideTextStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      selectedDecoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                      todayDecoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedDay != null) {
                        _selectedDay = _selectedDay!.subtract(const Duration(days: 1));
                        _focusedDay = _selectedDay!;
                      }
                    });
                  },
                  icon: Icon(Icons.chevron_left_rounded, color: theme.colorScheme.primary),
                  style: IconButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerHighest),
                ),
                Expanded(
                  child: Text(
                    _selectedDay != null
                        ? '${ZsebtunApp.formatDate(_selectedDay!)} (${DateFormat('EEEE', ZsebtunApp.localeString).format(_selectedDay!)})'
                        : tr('select_day'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedDay != null) {
                        _selectedDay = _selectedDay!.add(const Duration(days: 1));
                        _focusedDay = _selectedDay!;
                      }
                    });
                  },
                  icon: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary),
                  style: IconButton.styleFrom(backgroundColor: theme.colorScheme.surfaceContainerHighest),
                ),
              ],
            ),
          ),

          Expanded(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: selectedDayEvents.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_busy_rounded, size: 72, color: theme.colorScheme.surfaceContainerHighest),
                    const SizedBox(height: 16),
                    Text(tr('no_classes'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16)),
                  ],
                ),
              )
                  : ValueListenableBuilder<bool>(
                valueListenable: ZsebtunApp.newRoomsNotifier,
                builder: (context, useNewRooms, child) {
                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: selectedDayEvents.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final event = selectedDayEvents[index];
                      final dtStart = event['dtstart'] as DateTime;
                      final dtEnd = event['dtend'] as DateTime;

                      final startTime = ZsebtunApp.formatTime(dtStart);
                      final endTime = ZsebtunApp.formatTime(dtEnd);

                      final isZh = event['isZh'] == 1 || event['classType'] == 'ZH';
                      final defaultZhColor = ZsebtunApp.zhColorNotifier.value;
                      final itemColor = isZh
                          ? (event['color'] != null ? Color(event['color'] as int) : defaultZhColor)
                          : theme.colorScheme.primary;

                      final className = event['className']?.toString() ?? tr('unknown_class');
                      final classType = event['classType']?.toString() ?? '';
                      final eventType = event['eventType']?.toString() ?? '';
                      final roomsList = (event['rooms'] as List<dynamic>?) ?? <dynamic>[];

                      final location = roomsList.isNotEmpty
                          ? roomsList.map((r) {
                        final raw = r is Map ? (r['raw']?.toString() ?? '') : r.toString();
                        return useNewRooms ? raw : RoomFormatterService.formatRoomName(raw);
                      }).join(', ')
                          : tr('unknown_room');

                      final teachers = (event['teachers'] as List<dynamic>?) ?? <dynamic>[];

                      return Container(
                        decoration: BoxDecoration(
                          color: isZh
                              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: isZh
                              ? Border.all(color: itemColor.withValues(alpha: 0.4), width: 1.5)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showEventDetails(context, event),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 68,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          startTime,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: itemColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          endTime,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    width: 3,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isZh ? itemColor : theme.colorScheme.tertiary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          children: [
                                            Text(
                                              className,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: theme.colorScheme.onSurface,
                                              ),
                                            ),
                                            if (isZh)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: itemColor.withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  eventType.isNotEmpty ? eventType : 'ZH',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: itemColor,
                                                  ),
                                                ),
                                              )
                                            else if (classType.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.secondaryContainer,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  classType,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: theme.colorScheme.onSecondaryContainer,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.location_on, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                location,
                                                style: TextStyle(
                                                  color: theme.colorScheme.onSurfaceVariant,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (teachers.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.person, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  teachers.map((t) => t.toString()).join(', '),
                                                  style: TextStyle(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

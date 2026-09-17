import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../main.dart';
import 'setup_page.dart';
import 'settings_page.dart';
import '../database/db_helper.dart';
import '../services/ics_parser_service.dart';
import '../services/room_formatter_service.dart';

/// @description The full schedule view that allows users to navigate through their
/// classes using a monthly or weekly calendar, and view daily event details.
class CalendarPage extends StatefulWidget {
  /// @description Optional list of events passed from the Dashboard to eliminate
  /// database loading time during page navigation.
  final List<Map<String, dynamic>>? preloadedEvents;

  const CalendarPage({super.key, this.preloadedEvents});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.week;
  String _selectedView = 'weekly';
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<Map<String, dynamic>>> _groupedEvents = {};
  late bool _isLoading;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;

    if (widget.preloadedEvents != null && widget.preloadedEvents!.isNotEmpty) {
      _isLoading = false;
      _groupEventsByDate(widget.preloadedEvents!);
    } else {
      _isLoading = true;
      _loadOfflineEvents();
    }

    // Defer the heavy network request and ICS parsing until after the
    // page transition animation completes to prevent UI stuttering.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _fetchCalendar();
      });
    });
  }

  /// @description Retrieves saved events from the local SQLite database.
  Future<void> _loadOfflineEvents() async {
    final offlineEvents = await DatabaseHelper.instance.getEvents();
    if (offlineEvents.isNotEmpty) {
      _groupEventsByDate(offlineEvents);
      setState(() {
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

  /// @description Parses the downloaded ICS data using the IcsParserService,
  /// saves the new events to the database, and refreshes the UI.
  /// @param icsData The raw multi-line string content of the .ics file.
  Future<void> _parseICS(String icsData) async {
    final formattedEvents = IcsParserService.parseNeptunIcs(icsData);
    await DatabaseHelper.instance.saveEvents(formattedEvents);

    if (mounted) {
      _groupEventsByDate(formattedEvents);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// @description Groups a flat list of events into a Map indexed by the date (ignoring time)
  /// to allow quick lookup by the TableCalendar widget.
  /// @param flatEvents A list of un-grouped event maps.
  void _groupEventsByDate(List<Map<String, dynamic>> flatEvents) {
    Map<DateTime, List<Map<String, dynamic>>> newGroups = {};
    for (var event in flatEvents) {
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
    return _groupedEvents[normalizedDay] ?? [];
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
        MaterialPageRoute(builder: (context) => const SetupPage()),
            (route) => false,
      );
    }
  }

  /// @description Displays a bottom sheet modal containing full details of a clicked event.
  /// @param context The build context for the modal.
  /// @param event The data map representing the clicked class.
  void _showEventDetails(BuildContext context, Map<String, dynamic> event) {
    final theme = Theme.of(context);
    final startTime = DateFormat('HH:mm').format(event['dtstart'] as DateTime);
    final endTime = DateFormat('HH:mm').format(event['dtend'] as DateTime);
    final date = DateFormat(tr('date_format'), ZsebtunApp.localeString).format(event['dtstart'] as DateTime);

    final className = event['className'] ?? tr('unknown_class');
    final classType = event['classType']?.toString() ?? '';
    final eventType = event['eventType']?.toString() ?? '';
    final roomsList = event['rooms'] as List<dynamic>? ?? [];
    final teachers = event['teachers'] as List<dynamic>? ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
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
                      Text(
                        className,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                      ),
                      const SizedBox(height: 32),
                      _buildDetailRow(theme, Icons.access_time_rounded, '$date\n$startTime - $endTime'),
                      const SizedBox(height: 20),
                      if (roomsList.isNotEmpty)
                        _buildDetailRow(
                            theme,
                            Icons.location_on_rounded,
                            roomsList.map((r) => '${useNewRooms ? r['raw'] : RoomFormatterService.formatRoomName(r['raw'])}  •  ${r['floor']}').join('\n')
                        )
                      else
                        _buildDetailRow(theme, Icons.location_off_rounded, tr('unknown_room')),
                      const SizedBox(height: 20),
                      if (teachers.isNotEmpty)
                        _buildDetailRow(
                            theme,
                            Icons.person_rounded,
                            teachers.join('\n')
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                }
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

  @override
  Widget build(BuildContext context) {
    final selectedDayEvents = _selectedDay != null ? _getEventsForDay(_selectedDay!) : [];
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
                items: ['daily', 'weekly', 'monthly'].map((String value) {
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
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage())
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
            Container(
              color: theme.colorScheme.surface,
              child: TableCalendar(
                locale: ZsebtunApp.localeString,
                firstDay: DateTime(currentYear - 3, 1, 1),
                lastDay: DateTime(currentYear + 3, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                startingDayOfWeek: StartingDayOfWeek.monday,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                eventLoader: _getEventsForDay,
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: theme.colorScheme.onSurface),
                  rightChevronIcon: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontWeight: FontWeight.bold),
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
                  todayTextStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                  markerDecoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
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
                        ? DateFormat(tr('date_format'), ZsebtunApp.localeString).format(_selectedDay!)
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
            child: Container(
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
                        final startTime = DateFormat('HH:mm').format(event['dtstart'] as DateTime);
                        final endTime = DateFormat('HH:mm').format(event['dtend'] as DateTime);

                        final className = event['className'] ?? tr('unknown_class');
                        final classType = event['classType']?.toString() ?? '';
                        final roomsList = event['rooms'] as List<dynamic>? ?? [];

                        // SAFE FORMATTING: Explicitly cast dynamic raw values to Strings
                        final location = roomsList.isNotEmpty
                            ? roomsList.map((r) => useNewRooms
                            ? r['raw'].toString()
                            : RoomFormatterService.formatRoomName(r['raw'].toString())).join(', ')
                            : tr('unknown_room');

                        final teachers = event['teachers'] as List<dynamic>? ?? [];

                        return Container(
                          decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
                              ]
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
                                      width: 56,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            startTime,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            endTime,
                                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16),
                                      width: 3,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.tertiary,
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
                                              if (classType.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme.secondaryContainer,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                      classType,
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSecondaryContainer)
                                                  ),
                                                )
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
                                                    teachers.join(', '),
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
                                          ]
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
                  }
              ),
            ),
          ),
        ],
      ),
    );
  }
}
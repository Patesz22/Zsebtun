import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../database/db_helper.dart';
import '../services/room_formatter_service.dart';
import 'zh_add_edit_page.dart';

/// @description Displays all registered midterms and exams chronologically,
/// using customized date patterns, time formats, and swipe-to-delete confirmation.
class ZhListPage extends StatefulWidget {
  const ZhListPage({super.key});

  @override
  State<ZhListPage> createState() => _ZhListPageState();
}

class _ZhListPageState extends State<ZhListPage> {
  List<Map<String, dynamic>> _zhEvents = [];
  List<String> _preloadedSubjects = [];
  bool _isLoading = true;

  static const Map<String, String> _typeTranslationKeys = {
    '1. ZH': 'type_midterm_1',
    '2. ZH': 'type_midterm_2',
    'PótZH': 'type_retake',
    'Vizsga': 'type_exam',
    'Egyéb': 'type_other',
  };

  /// @description Initializes page state and triggers background data loading.
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// @description Concurrently loads ZH records and active semester subjects into memory.
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        DatabaseHelper.instance.getZhEvents(),
        DatabaseHelper.instance.getCurrentSemesterSubjects(),
      ]);

      if (mounted) {
        setState(() {
          _zhEvents = results[0] as List<Map<String, dynamic>>;
          _preloadedSubjects = results[1] as List<String>;
        });
      }
    } catch (e) {
      debugPrint('Error loading ZH data: $e');
      if (mounted) {
        setState(() {
          _zhEvents = [];
          _preloadedSubjects = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// @description Converts arbitrary timestamp payloads to a standard DateTime.
  /// @param value Raw date timestamp or string.
  /// @returns Standardized DateTime instance.
  DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  /// @description Formats room identifiers according to the global room naming setting.
  /// @param roomsRaw Raw room JSON array or string.
  /// @param useNewRooms Flag determining if new room syntax should be displayed.
  /// @returns Formatted room string.
  String _formatRoom(dynamic roomsRaw, bool useNewRooms) {
    if (roomsRaw == null) return '';
    List<dynamic> roomsList = [];
    try {
      if (roomsRaw is List) {
        roomsList = roomsRaw;
      } else if (roomsRaw is String && roomsRaw.startsWith('[')) {
        roomsList = jsonDecode(roomsRaw) as List<dynamic>;
      } else if (roomsRaw is String && roomsRaw.isNotEmpty) {
        roomsList = [{'raw': roomsRaw}];
      }
    } catch (_) {}

    if (roomsList.isEmpty) return '';
    return roomsList.map((r) {
      final raw = r is Map ? (r['raw']?.toString() ?? '') : r.toString();
      return useNewRooms ? raw : RoomFormatterService.formatRoomName(raw);
    }).where((s) => s.isNotEmpty).join(', ');
  }

  /// @description Prompts the user with an alert dialog before confirming record deletion.
  /// @param context The active build context.
  /// @returns True if deletion is confirmed, false otherwise.
  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_zh_title')),
        content: Text(tr('delete_zh_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
  }

  /// @description Navigates to the creation page using preloaded subject suggestions.
  Future<void> _openAddPage() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ZhAddEditPage(preloadedSubjects: _preloadedSubjects),
      ),
    );
    if (changed == true) {
      _loadData();
    }
  }

  /// @description Navigates to the edit page with prefilled event properties.
  /// @param event Map containing attributes of the event to edit.
  Future<void> _openEditPage(Map<String, dynamic> event) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ZhAddEditPage(
          existingEvent: event,
          preloadedSubjects: _preloadedSubjects,
        ),
      ),
    );
    if (changed == true) {
      _loadData();
    }
  }

  /// @description Builds the main scaffold containing the list of examinations.
  /// @param context The active build context.
  /// @returns The complete scaffold widget.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultZhColor = ZsebtunApp.zhColorNotifier.value;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          tr('zh_list'),
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: tr('add_zh'),
            icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
            onPressed: _openAddPage,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: defaultZhColor))
          : _zhEvents.isEmpty
          ? _buildEmptyState(theme, defaultZhColor)
          : ValueListenableBuilder<bool>(
        valueListenable: ZsebtunApp.newRoomsNotifier,
        builder: (context, useNewRooms, _) {
          return ValueListenableBuilder<String>(
            valueListenable: ZsebtunApp.dateFormatNotifier,
            builder: (context, datePattern, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: ZsebtunApp.use24HourFormatNotifier,
                builder: (context, use24h, _) {
                  return RefreshIndicator(
                    color: defaultZhColor,
                    onRefresh: _loadData,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _zhEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final event = _zhEvents[index];
                        final start = _parseDateTime(event['dtstart']);
                        final end = _parseDateTime(event['dtend']);
                        final isPast = end.isBefore(now);
                        final location = _formatRoom(event['rooms'], useNewRooms);

                        final itemColor = event['color'] != null
                            ? Color(event['color'] as int)
                            : defaultZhColor;

                        final eventType = event['eventType']?.toString();
                        final displayType = eventType != null && _typeTranslationKeys.containsKey(eventType)
                            ? tr(_typeTranslationKeys[eventType]!)
                            : eventType;

                        final weekday = DateFormat('EEEE', ZsebtunApp.localeString).format(start);

                        return Dismissible(
                          key: ValueKey(event['id'] ?? index),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) => _confirmDelete(context),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                          onDismissed: (_) async {
                            if (event['id'] != null) {
                              await DatabaseHelper.instance.deleteZhEvent(event['id'] as int);
                            }
                            _zhEvents.removeAt(index);
                          },
                          child: InkWell(
                            onTap: () => _openEditPage(event),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isPast
                                    ? theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.6)
                                    : theme.colorScheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isPast
                                      ? theme.colorScheme.outlineVariant.withValues(alpha: 0.2)
                                      : itemColor.withValues(alpha: 0.4),
                                  width: isPast ? 1 : 1.5,
                                ),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      decoration: BoxDecoration(
                                        color: isPast ? theme.colorScheme.outlineVariant : itemColor,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          bottomLeft: Radius.circular(16),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  '${ZsebtunApp.formatDate(start)} ($weekday)',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: isPast ? theme.colorScheme.onSurfaceVariant : itemColor,
                                                  ),
                                                ),
                                                Text(
                                                  '${ZsebtunApp.formatTime(start)} - ${ZsebtunApp.formatTime(end)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                if (displayType != null &&
                                                    displayType.isNotEmpty &&
                                                    displayType != 'ZH') ...[
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    margin: const EdgeInsets.only(right: 8),
                                                    decoration: BoxDecoration(
                                                      color: itemColor.withValues(alpha: 0.18),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      displayType,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: itemColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    event['className']?.toString() ?? tr('unknown_class'),
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: isPast
                                                          ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                                                          : theme.colorScheme.onSurface,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (location.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.location_on_outlined,
                                                    size: 14,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    location,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: defaultZhColor,
        tooltip: tr('add_zh'),
        onPressed: _openAddPage,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  /// @description Renders a watermark icon and helpful description when no exams exist.
  /// @param theme Active application theme data.
  /// @param zhColor Primary color assigned to examination events.
  /// @returns The empty state view widget.
  Widget _buildEmptyState(ThemeData theme, Color zhColor) {
    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: Opacity(
              opacity: 0.04,
              child: Icon(
                Icons.assignment_turned_in_rounded,
                size: 260,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: zhColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.event_note_rounded,
                    size: 48,
                    color: zhColor.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('no_zh_found'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('add_first_zh_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: zhColor,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _openAddPage,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text(
                    tr('add_zh'),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
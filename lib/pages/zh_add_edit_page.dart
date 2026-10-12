import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../database/db_helper.dart';

/// @description Form page to create or update an exam using localized date, time, and calendar options.
class ZhAddEditPage extends StatefulWidget {
  final Map<String, dynamic>? existingEvent;
  final List<String>? preloadedSubjects;

  const ZhAddEditPage({
    super.key,
    this.existingEvent,
    this.preloadedSubjects,
  });

  @override
  State<ZhAddEditPage> createState() => _ZhAddEditPageState();
}

class _ZhAddEditPageState extends State<ZhAddEditPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _roomController;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Color _selectedColor;
  String _selectedType = '1. ZH';

  List<String> _semesterSubjects = [];
  bool _isLoadingSubjects = true;

  static const List<String> _examTypes = ['1. ZH', '2. ZH', 'PótZH', 'Vizsga', 'Egyéb'];

  static const Map<String, String> _typeTranslationKeys = {
    '1. ZH': 'type_midterm_1',
    '2. ZH': 'type_midterm_2',
    'PótZH': 'type_retake',
    'Vizsga': 'type_exam',
    'Egyéb': 'type_other',
  };

  static const List<Color> _presetColors = [
    Color(0xFFE53935), // Red
    Color(0xFFD81B60), // Pink
    Color(0xFF8E24AA), // Purple
    Color(0xFF1E88E5), // Blue
    Color(0xFF00ACC1), // Cyan
    Color(0xFF43A047), // Green
    Color(0xFFFB8C00), // Orange
    Color(0xFF6D4C41), // Brown
  ];

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;

    _selectedColor = event?['color'] != null
        ? Color(event!['color'] as int)
        : ZsebtunApp.zhColorNotifier.value;

    if (event != null) {
      _nameController = TextEditingController(text: event['className'] ?? '');
      _roomController = TextEditingController(text: _extractRoom(event['rooms']));

      final dtStart = _parseDate(event['dtstart']);
      final dtEnd = _parseDate(event['dtend']);

      _selectedDate = dtStart;
      _startTime = TimeOfDay(hour: dtStart.hour, minute: dtStart.minute);
      _endTime = TimeOfDay(hour: dtEnd.hour, minute: dtEnd.minute);

      final rawType = event['eventType']?.toString();
      if (rawType != null && _examTypes.contains(rawType)) {
        _selectedType = rawType;
      } else {
        final className = event['className']?.toString() ?? '';
        for (final type in _examTypes) {
          if (className.contains(type)) {
            _selectedType = type;
            break;
          }
        }
      }
    } else {
      _nameController = TextEditingController();
      _roomController = TextEditingController();

      _selectedDate = DateTime.now();
      _startTime = const TimeOfDay(hour: 18, minute: 0);
      _endTime = const TimeOfDay(hour: 20, minute: 0);
    }

    if (widget.preloadedSubjects != null && widget.preloadedSubjects!.isNotEmpty) {
      _semesterSubjects = List.from(widget.preloadedSubjects!);
      _isLoadingSubjects = false;
    } else {
      _loadSemesterSubjects();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  /// @description Converts raw string, integer timestamp, or DateTime objects into a DateTime instance.
  DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  /// @description Safely unpacks room descriptions from legacy JSON lists or plain text attributes.
  String _extractRoom(dynamic roomsRaw) {
    if (roomsRaw == null) return '';
    try {
      if (roomsRaw is String && roomsRaw.startsWith('[')) {
        final decoded = jsonDecode(roomsRaw) as List<dynamic>;
        if (decoded.isNotEmpty) {
          return decoded.first['raw']?.toString() ?? '';
        }
      }
    } catch (_) {}
    return roomsRaw.toString();
  }

  /// @description Asynchronously retrieves enrolled subjects for chip recommendations.
  Future<void> _loadSemesterSubjects() async {
    try {
      final subjects = await DatabaseHelper.instance.getCurrentSemesterSubjects();
      if (mounted) {
        setState(() {
          _semesterSubjects = subjects;
          _isLoadingSubjects = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSubjects = false);
    }
  }

  /// @description Shows date picker configured with the customized first day of the week and 24h format.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: ZsebtunApp.getCalendarPickerLocale(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: ZsebtunApp.use24HourFormatNotifier.value,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  /// @description Shows time picker configured with the active 24-hour or 12-hour setting for start time.
  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: ZsebtunApp.use24HourFormatNotifier.value,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        final startMinutes = _startTime.hour * 60 + _startTime.minute;
        final endMinutes = _endTime.hour * 60 + _endTime.minute;
        if (endMinutes <= startMinutes) {
          _endTime = TimeOfDay(
            hour: (_startTime.hour + 2) % 24,
            minute: _startTime.minute,
          );
        }
      });
    }
  }

  /// @description Shows time picker configured with the active 24-hour or 12-hour setting for end time.
  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: ZsebtunApp.use24HourFormatNotifier.value,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  /// @description Validates entry inputs and persists changes to SQLite.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('invalid_time_range'))),
      );
      return;
    }

    final dtStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final dtEnd = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    final eventData = <String, dynamic>{
      'className': _nameController.text.trim(),
      'dtstart': dtStart.toIso8601String(),
      'dtend': dtEnd.toIso8601String(),
      'classType': 'ZH',
      'eventType': _selectedType,
      'rooms': jsonEncode([
        {'raw': _roomController.text.trim()}
      ]),
      'isZh': 1,
      'color': _selectedColor.toARGB32(),
    };

    if (widget.existingEvent != null && widget.existingEvent!['id'] != null) {
      await DatabaseHelper.instance.updateZhEvent(widget.existingEvent!['id'] as int, eventData);
    } else {
      await DatabaseHelper.instance.insertZhEvent(eventData);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  /// @description Prompts deletion confirmation and removes the record from SQLite.
  Future<void> _delete() async {
    if (widget.existingEvent?['id'] == null) return;

    final confirmed = await showDialog<bool>(
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteZhEvent(widget.existingEvent!['id'] as int);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingEvent != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isEditing ? tr('edit_zh') : tr('new_zh'),
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          if (isEditing)
            IconButton(
              tooltip: tr('delete'),
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            if (!_isLoadingSubjects && _semesterSubjects.isNotEmpty) ...[
              Text(
                tr('semester_subjects_hint'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _semesterSubjects.map((subject) {
                  return ActionChip(
                    label: Text(subject),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide.none,
                    onPressed: () {
                      setState(() {
                        _nameController.text = subject;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: tr('course_name'),
                prefixIcon: const Icon(Icons.assignment_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? tr('course_name_required') : null,
            ),
            const SizedBox(height: 16),

            Text(
              tr('type'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _examTypes.map((type) {
                final isSelected = _selectedType == type;
                final labelText = _typeTranslationKeys.containsKey(type)
                    ? tr(_typeTranslationKeys[type]!)
                    : type;

                return ChoiceChip(
                  label: Text(labelText),
                  selected: isSelected,
                  selectedColor: _selectedColor.withValues(alpha: 0.25),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _selectedType = type);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(Icons.calendar_today_rounded, color: _selectedColor),
                title: Text(tr('date'), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: ValueListenableBuilder<String>(
                  valueListenable: ZsebtunApp.dateFormatNotifier,
                  builder: (context, pattern, _) {
                    final weekday = DateFormat('EEEE', ZsebtunApp.localeString).format(_selectedDate);
                    return Text('${ZsebtunApp.formatDate(_selectedDate)} ($weekday)');
                  },
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(tr('start_time'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: ValueListenableBuilder<bool>(
                        valueListenable: ZsebtunApp.use24HourFormatNotifier,
                        builder: (context, _, __) {
                          return Text(
                            ZsebtunApp.formatTimeOfDay(_startTime),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                      onTap: _pickStartTime,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(tr('end_time'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: ValueListenableBuilder<bool>(
                        valueListenable: ZsebtunApp.use24HourFormatNotifier,
                        builder: (context, _, __) {
                          return Text(
                            ZsebtunApp.formatTimeOfDay(_endTime),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                      onTap: _pickEndTime,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _roomController,
              decoration: InputDecoration(
                labelText: tr('room_optional'),
                prefixIcon: const Icon(Icons.room_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
              ),
            ),
            const SizedBox(height: 20),

            Text(
              tr('custom_color'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: _presetColors.map((color) {
                final isSelected = _selectedColor.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _selectedColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                isEditing ? tr('save_changes') : tr('save_zh'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/foundation.dart';

/// @description Service for parsing Neptun-specific ICS calendar exports using Regular Expressions.
class IcsParserService {
  static final _unfoldRegex = RegExp(r'\r?\n ');
  static final _veventRegex = RegExp(r'BEGIN:VEVENT(.*?)END:VEVENT', dotAll: true);

  static final _dtstartRegex = RegExp(r'DTSTART.*?:([^\r\n]+)');
  static final _dtendRegex = RegExp(r'DTEND.*?:([^\r\n]+)');
  static final _locationRegex = RegExp(r'LOCATION:([^\r\n]*)');
  static final _summaryRegex = RegExp(r'SUMMARY:([^\r\n]+)');

  static final _adminTaskRegex = RegExp(r'Határidő');
  static final _fullSummaryRegex = RegExp(r'^(.*?)\s*\((.*?)\)\s*-\s*(.*?)\s*-\s*(.*)$');
  static final _noTeacherSummaryRegex = RegExp(r'^(.*?)\s*\((.*?)\)\s*-\s*(.*)$');

  static final _iBuildingRegex = RegExp(r'^I.*?(\d)');
  static final _hyphenBuildingRegex = RegExp(r'-(\d)-');
  static final _eBuildingRegex = RegExp(r'^E.*?(\d)');

  /// @description Parses a raw .ics string from Neptun into a structured list of events.
  /// @param icsData The raw multi-line string content of the .ics file.
  /// @returns A chronologically sorted list of event maps containing separated class data.
  static List<Map<String, dynamic>> parseNeptunIcs(String icsData) {
    List<Map<String, dynamic>> parsedEvents = [];

    // Fix ICS multi-line formatting before passing to extraction regex
    final unfoldedData = icsData.replaceAll(_unfoldRegex, '');
    final events = _veventRegex.allMatches(unfoldedData);

    for (final match in events) {
      final eventBody = match.group(1) ?? '';

      final summaryMatch = _summaryRegex.firstMatch(eventBody);
      final summaryStr = summaryMatch?.group(1)?.trim() ?? '';

      if (_adminTaskRegex.hasMatch(summaryStr)) continue;

      Map<String, dynamic> currentEvent = {};

      final fullMatch = _fullSummaryRegex.firstMatch(summaryStr);
      final noTeacherMatch = _noTeacherSummaryRegex.firstMatch(summaryStr);

      if (fullMatch != null) {
        currentEvent['className'] = fullMatch.group(1)?.trim();
        currentEvent['classType'] = fullMatch.group(2)?.replaceAll('-', '').trim();
        currentEvent['teachers'] = fullMatch.group(3)?.split(RegExp(r'[;,]')).map((e) => e.trim()).toList() ?? [];
        currentEvent['eventType'] = fullMatch.group(4)?.trim();
      } else if (noTeacherMatch != null) {
        currentEvent['className'] = noTeacherMatch.group(1)?.trim();
        currentEvent['classType'] = noTeacherMatch.group(2)?.replaceAll('-', '').trim();
        currentEvent['teachers'] = <String>[];
        currentEvent['eventType'] = noTeacherMatch.group(3)?.trim();
      } else {
        currentEvent['className'] = summaryStr.isEmpty ? 'Unknown' : summaryStr;
        currentEvent['classType'] = '';
        currentEvent['teachers'] = <String>[];
        currentEvent['eventType'] = 'Egyéb';
      }

      final dtstartMatch = _dtstartRegex.firstMatch(eventBody);
      final dtendMatch = _dtendRegex.firstMatch(eventBody);

      if (dtstartMatch != null) {
        currentEvent['dtstart'] = _parseIcsDate(dtstartMatch.group(1)!);
        currentEvent['dtend'] = dtendMatch != null ? _parseIcsDate(dtendMatch.group(1)!) : currentEvent['dtstart'];
      } else {
        continue;
      }

      final locationMatch = _locationRegex.firstMatch(eventBody);
      final rawLocation = locationMatch?.group(1)?.trim() ?? '';

      currentEvent['rooms'] = rawLocation.isEmpty
          ? []
          : rawLocation.split(',').map((r) => _parseRoomData(r.trim())).toList();

      parsedEvents.add(currentEvent);
    }

    parsedEvents.sort((a, b) => (a['dtstart'] as DateTime).compareTo(b['dtstart'] as DateTime));
    return parsedEvents;
  }

  /// @description Converts a raw ICS datetime string into a local Dart DateTime object.
  /// @param rawDate The datetime string from the ICS file (e.g., '20260114T070000Z').
  /// @returns The parsed DateTime converted to the device's local timezone.
  static DateTime _parseIcsDate(String rawDate) {
    try {
      final cleanDate = rawDate.replaceAll('Z', '');
      if (cleanDate.length >= 15) {
        return DateTime.utc(
          int.parse(cleanDate.substring(0, 4)),
          int.parse(cleanDate.substring(4, 6)),
          int.parse(cleanDate.substring(6, 8)),
          int.parse(cleanDate.substring(9, 11)),
          int.parse(cleanDate.substring(11, 13)),
        ).toLocal();
      }
    } catch (e) {
      debugPrint('Date parse error: $e');
    }
    return DateTime.now();
  }

  /// @description Applies BME-specific heuristics to extract floor information from a room string.
  /// @param room The raw room identifier string (e.g., 'IB028', 'Q-AB-2-I').
  /// @returns A map containing both the raw room identifier and the calculated floor string.
  static Map<String, String> _parseRoomData(String room) {
    String floor = "?";

    if (_iBuildingRegex.hasMatch(room)) {
      final match = _iBuildingRegex.firstMatch(room)!.group(1)!;
      floor = match == '0' ? 'Földszint' : '$match. emelet';
    } else if (_hyphenBuildingRegex.hasMatch(room)) {
      floor = '${_hyphenBuildingRegex.firstMatch(room)!.group(1)!}. emelet';
    } else if (_eBuildingRegex.hasMatch(room)) {
      floor = '${_eBuildingRegex.firstMatch(room)!.group(1)!}. emelet';
    }

    return {
      'raw': room,
      'floor': floor,
    };
  }
}
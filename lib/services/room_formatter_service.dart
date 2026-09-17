import 'package:flutter/foundation.dart';

/// @description Service to normalize and format complex university classroom names.
class RoomFormatterService {

  /// @description Normalizes complex classroom names into a standard format: [Building][Wing]-[Floor][Room].
  /// Includes special heuristics for Q building roman numerals and E building lecture halls.
  /// @param rawRoom The raw room identifier string directly from the exported ICS file.
  /// @returns The cleaned and formatted room string.
  static String formatRoomName(String rawRoom) {
    if (rawRoom.trim().isEmpty) return rawRoom;

    final normalizedRaw = rawRoom.trim().toUpperCase();

    // Special Case: Q building large lecture halls (Q-AB-2/4-I/II -> Q-II)
    if (normalizedRaw.startsWith('Q')) {
      final qMatch = RegExp(r'(I|II|III|IV|V)$').firstMatch(normalizedRaw);
      if (qMatch != null) {
        return 'Q-${qMatch.group(1)}';
      }
    }

    // Special Case: E (E-1-01-B -> E1B)
    if (normalizedRaw.startsWith('E')) {
      // Group 1: Floor number
      // Group 2: Room letter
      // Accepts any non-alphanumeric separators in between
      final eMatch = RegExp(r'^E[^A-Z0-9]*(\d)[^A-Z0-9]*0?1?[^A-Z0-9]*([A-Z])$').firstMatch(normalizedRaw);
      if (eMatch != null) {
        return 'E${eMatch.group(1)}${eMatch.group(2)}';
      }
    }

    // General Case Regex:
    // Group 1: Building (1 letter)
    // Group 2: Wing (1-2 letters, optional)
    // Group 3: Floor (1 char, letter or number)
    // Group 4: Room (1-5 chars)
    final generalRegex = RegExp(r'^([A-Z])[^A-Z0-9]*([A-Z]{1,2})?[^A-Z0-9]*([A-Z0-9])[^A-Z0-9]*([A-Z0-9]{1,5})$');
    final match = generalRegex.firstMatch(normalizedRaw);

    if (match != null) {
      final building = match.group(1)!;
      final wing = match.group(2) ?? '';

      String floor = match.group(3)!;
      if (floor == 'F') floor = '0'; // Convert Ground Floor (F) to 0

      String room = match.group(4)!;

      // Clean up redundancy (Floor 4, Room 406 -> Room 06)
      if (room.startsWith(floor) && room.length > floor.length) {
        room = room.substring(floor.length);
      }

      // Pad isolated single-digit room numbers (Floor 0, Room 8 -> 028)
      if (room.length == 1 && RegExp(r'^\d$').hasMatch(room)) {
        room = room.padLeft(2, '0');
      }

      return '$building$wing-$floor$room';
    }

    // Return the original string if it doesn't match the standard layout
    return rawRoom;
  }
}
import 'package:intl/intl.dart';

/// Centralized date and time formatting utilities for ValAPP.
class DateTimeUtils {
  DateTimeUtils._();

  static final DateFormat _matchDate = DateFormat('MMM d, HH:mm');
  static final DateFormat _dateTime = DateFormat('MMM d, yyyy HH:mm');
  static final DateFormat _newsDate = DateFormat('MMM d, yyyy');

  /// Formats epoch milliseconds as 'MMM d, HH:mm' (e.g. 'Aug 16, 16:04').
  static String formatMatchTime(int epochMillis) {
    if (epochMillis <= 0) return 'Recently';
    return _matchDate.format(DateTime.fromMillisecondsSinceEpoch(epochMillis));
  }

  /// Formats DateTime as 'MMM d, yyyy HH:mm' (e.g. 'Aug 16, 2026 16:04').
  static String formatFullDateTime(DateTime? dateTime, {String fallback = 'Indefinite'}) {
    if (dateTime == null) return fallback;
    return _dateTime.format(dateTime);
  }

  /// Formats DateTime as 'MMM d, yyyy' (e.g. 'Aug 16, 2026').
  static String formatNewsDate(DateTime? dateTime, {String fallback = ''}) {
    if (dateTime == null) return fallback;
    return _newsDate.format(dateTime);
  }
}

/// Helpers for resolving and validating Riot ID display names.
class DisplayNameUtil {
  DisplayNameUtil._();

  static bool isPlaceholder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed == 'Valorant Player' || trimmed == 'Valorant Account') {
      return true;
    }
    return RegExp(
      r'^(Account|Player) \([0-9a-fA-F]{4,6}(\.\.\.)?\)$',
    ).hasMatch(trimmed);
  }
}

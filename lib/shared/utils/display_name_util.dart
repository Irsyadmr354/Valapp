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

  static String? fromUserInfo(Map<String, dynamic> payload) {
    final acct = payload['acct'];
    if (acct is! Map) return null;

    final gameName = acct['game_name']?.toString() ??
        acct['gameName']?.toString() ??
        '';
    final tagLine =
        acct['tag_line']?.toString() ?? acct['tagLine']?.toString() ?? '';

    if (gameName.isEmpty) return null;
    return tagLine.isNotEmpty ? '$gameName#$tagLine' : gameName;
  }
}

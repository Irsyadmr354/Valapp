/// Helper for case/dash-insensitive UUID lookup (Valorant IDs).
/// Riot payloads vary: exact, lowercase, stripped-dash-lowercase.
/// Use this single helper instead of duplicating 3-variant chains.
T? lookupByUuid<T>(Map<String, dynamic> map, String uuid) {
  if (uuid.isEmpty) return null;
  return (map[uuid] as T?) ??
      (map[uuid.toLowerCase()] as T?) ??
      (map[uuid.replaceAll('-', '').toLowerCase()] as T?);
}

Map<String, dynamic>? lookupMap(Map<String, dynamic> map, String uuid) {
  final val = lookupByUuid<dynamic>(map, uuid);
  if (val is Map<String, dynamic>) return val;
  if (val is Map) return Map<String, dynamic>.from(val);
  return null;
}

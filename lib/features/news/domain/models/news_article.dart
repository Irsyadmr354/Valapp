/// A single Valorant news article or patch note.
class NewsArticle {
  final String uid;
  final String title;
  final String description;
  final String url;
  final String? bannerUrl;
  final String category;   // e.g. "game-updates", "esports", "announcements"
  final DateTime? publishedAt;

  const NewsArticle({
    required this.uid,
    required this.title,
    required this.description,
    required this.url,
    this.bannerUrl,
    required this.category,
    this.publishedAt,
  });

  bool get isPatchNote =>
      category.toLowerCase().contains('game-update') ||
      title.toLowerCase().contains('patch notes');

  String get categoryLabel {
    switch (category.toLowerCase()) {
      case 'game-updates':
        return 'PATCH NOTES';
      case 'esports':
        return 'ESPORTS';
      case 'announcements':
        return 'ANNOUNCEMENT';
      case 'dev-diaries':
      case 'dev-diary':
        return 'DEV DIARY';
      default:
        return category.replaceAll('-', ' ').toUpperCase();
    }
  }

  /// Parse from the `playvalorant.com` page-data JSON node.
  factory NewsArticle.fromPageData(Map<String, dynamic> json) {
    final node = json['node'] as Map<String, dynamic>? ?? json;

    // Url handling — API returns relative paths
    final rawUrl = node['url'] as String? ??
        node['path'] as String? ??
        node['link']?['url'] as String? ?? '';
    final fullUrl = rawUrl.startsWith('http')
        ? rawUrl
        : 'https://playvalorant.com$rawUrl';

    // Banner image
    String? bannerUrl;
    final banner = node['banner'] as Map<String, dynamic>? ??
        node['image'] as Map<String, dynamic>?;
    if (banner != null) {
      bannerUrl = banner['url'] as String? ??
          banner['dimension_url']?['url'] as String?;
    }

    // Date
    DateTime? publishedAt;
    final dateRaw = node['date'] as String? ??
        node['publish_date'] as String? ??
        node['publishedAt'] as String?;
    if (dateRaw != null) {
      publishedAt = DateTime.tryParse(dateRaw);
    }

    // Category
    final category = node['category'] as String? ??
        (node['tags'] as List<dynamic>?)
            ?.whereType<Map>()
            .firstWhere(
                (t) => t['type'] == 'category',
                orElse: () => {'title': 'news'})['title']
            ?.toString() ??
        'news';

    return NewsArticle(
      uid: node['uid'] as String? ??
          node['id'] as String? ??
          fullUrl.hashCode.toString(),
      title: node['title'] as String? ?? '',
      description: node['description'] as String? ??
          node['external_link'] as String? ?? '',
      url: fullUrl,
      bannerUrl: bannerUrl,
      category: category,
      publishedAt: publishedAt,
    );
  }
}

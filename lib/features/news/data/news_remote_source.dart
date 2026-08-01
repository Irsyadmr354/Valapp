import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/storage/cache_storage.dart';
import '../domain/models/news_article.dart';

class NewsRemoteSource {
  const NewsRemoteSource(this._dio);
  final Dio _dio;

  static const _cacheKey = 'valorant_news_feed';
  static const _cacheTimestampKey = 'valorant_news_feed_fetched_at';
  static const _cacheDuration = Duration(hours: 2);

  // playvalorant.com page-data API — returns structured JSON without scraping
  static const _pageDataUrl =
      'https://playvalorant.com/page-data/en-us/news/page-data.json';

  Future<List<NewsArticle>> fetchNews() async {
    final cache = CacheStorage.instance;

    // Cache-first: return cached data if fresh
    final isStale = await cache.isStale(_cacheTimestampKey, _cacheDuration);
    if (!isStale) {
      final cachedList = await cache.getJsonList(_cacheKey);
      if (cachedList != null && cachedList.isNotEmpty) {
        return _parseList(cachedList);
      }
    }

    try {
      final response = await _dio.get<dynamic>(
        _pageDataUrl,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = _toMap(response.data);
      final result = data['result'] as Map<String, dynamic>? ?? {};
      final pageContext =
          result['pageContext'] as Map<String, dynamic>? ?? {};
      final newsResult =
          pageContext['newsResult'] as Map<String, dynamic>? ?? {};
      final edges =
          (newsResult['edges'] as List<dynamic>?) ??
          (data['data']?['allNewsEntries']?['edges'] as List<dynamic>?) ??
          [];

      if (edges.isEmpty) {
        // Fallback: try to find articles anywhere in the JSON tree
        return _fallbackParse(data);
      }

      final articles = edges
          .whereType<Map<String, dynamic>>()
          .map(NewsArticle.fromPageData)
          .where((a) => a.title.isNotEmpty)
          .toList();

      if (articles.isNotEmpty) {
        await cache.setJson(_cacheKey, articles.map(_toJson).toList());
        await cache.setTimestamp(_cacheTimestampKey);
      }

      return articles;
    } catch (_) {
      // Network failed — return cached data if available (even if stale)
      final cachedList = await cache.getJsonList(_cacheKey);
      if (cachedList != null) return _parseList(cachedList);
      return [];
    }
  }

  List<NewsArticle> _fallbackParse(Map<String, dynamic> root) {
    // Walk the JSON tree looking for nodes with 'title' + 'url' keys
    final found = <NewsArticle>[];
    void walk(dynamic node) {
      if (found.length >= 20) return;
      if (node is Map<String, dynamic>) {
        if (node.containsKey('title') &&
            node.containsKey('url') &&
            (node['title'] as String? ?? '').isNotEmpty) {
          try {
            found.add(NewsArticle.fromPageData(node));
          } catch (_) {}
        }
        for (final v in node.values) { walk(v); }
      } else if (node is List) {
        for (final item in node) { walk(item); }
      }
    }
    walk(root);
    return found.where((a) => a.title.isNotEmpty).toList();
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
    }
    return {};
  }

  List<NewsArticle> _parseList(List<dynamic> list) {
    return list
        .whereType<Map<String, dynamic>>()
        .map((json) => NewsArticle(
              uid: json['uid'] as String? ?? '',
              title: json['title'] as String? ?? '',
              description: json['description'] as String? ?? '',
              url: json['url'] as String? ?? '',
              bannerUrl: json['bannerUrl'] as String?,
              category: json['category'] as String? ?? 'news',
              publishedAt: json['publishedAt'] != null
                  ? DateTime.tryParse(json['publishedAt'] as String)
                  : null,
            ))
        .where((a) => a.title.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _toJson(NewsArticle a) => {
        'uid': a.uid,
        'title': a.title,
        'description': a.description,
        'url': a.url,
        'bannerUrl': a.bannerUrl,
        'category': a.category,
        'publishedAt': a.publishedAt?.toIso8601String(),
      };
}

import 'package:dio/dio.dart';
import '../../../core/network/api_response_decoder.dart';
import '../../../core/storage/cache_storage.dart';
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
      final fresh = await _loadCached(cache);
      if (fresh != null) return fresh;
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

      final data =
          ApiResponseDecoder.decodeMap(response.data, source: _pageDataUrl);
      final result = _asMap(data['result']);
      final pageContext = _asMap(result['pageContext']);
      final newsResult = _asMap(pageContext['newsResult']);
      final allNewsEntries = _asMap(_asMap(data['data'])['allNewsEntries']);
      final edges = _asList(newsResult['edges']) ??
          _asList(allNewsEntries['edges']) ??
          const <dynamic>[];

      if (edges.isEmpty) {
        final articles = _fallbackParse(data);
        if (articles.isEmpty) {
          throw const FormatException('News response contained no articles');
        }
        await cache.setJson(_cacheKey, articles.map(_toJson).toList());
        await cache.setTimestamp(_cacheTimestampKey);
        return articles;
      }

      final articles = edges
          .whereType<Map>()
          .map((entry) =>
              NewsArticle.fromPageData(Map<String, dynamic>.from(entry)))
          .where(_isValidArticle)
          .toList();

      if (articles.isEmpty) {
        throw const FormatException('News response contained no articles');
      }
      await cache.setJson(_cacheKey, articles.map(_toJson).toList());
      await cache.setTimestamp(_cacheTimestampKey);
      return articles;
    } catch (_) {
      final stale = await _loadCached(cache);
      if (stale != null) return stale;
      return [];
    }
  }

  List<NewsArticle> _fallbackParse(Map<String, dynamic> root) {
    // Walk the JSON tree looking for nodes with 'title' + 'url' keys
    final found = <NewsArticle>[];
    void walk(dynamic node) {
      if (found.length >= 20) return;
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        if (map['title'] is String && map['url'] is String) {
          try {
            final article = NewsArticle.fromPageData(map);
            if (_isValidArticle(article)) found.add(article);
          } catch (_) {}
        }
        for (final v in map.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(root);
    return found;
  }

  List<NewsArticle> _parseList(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .where((json) => json['title'] is String && json['url'] is String)
        .map((json) => NewsArticle(
            uid: json['uid']?.toString() ?? '',
            title: json['title'] as String,
            description: json['description']?.toString() ?? '',
            url: json['url'] as String,
            bannerUrl: json['bannerUrl'] as String?,
            category: json['category']?.toString() ?? 'news',
            publishedAt:
                DateTime.tryParse(json['publishedAt']?.toString() ?? '')))
        .where(_isValidArticle)
        .toList();
  }

  Future<List<NewsArticle>?> _loadCached(CacheStorage cache) async {
    final cached = await cache.getJsonList(_cacheKey);
    if (cached == null) return null;
    final articles = _parseList(cached);
    if (articles.isNotEmpty) return articles;
    await cache.remove(_cacheKey);
    await cache.remove(_cacheTimestampKey);
    return null;
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  List<dynamic>? _asList(dynamic value) =>
      value is List ? List<dynamic>.from(value) : null;

  bool _isValidArticle(NewsArticle article) =>
      article.title.isNotEmpty && article.url.startsWith('http');

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

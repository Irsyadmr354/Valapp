import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valorant_app/core/storage/cache_storage.dart';
import 'package:valorant_app/features/news/data/news_remote_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheStorage.instance.clearAll();
  });

  test('returns stale valid news when the network request fails', () async {
    final cache = CacheStorage.instance;
    await cache.setJson('valorant_news_feed', [
      {
        'uid': 'article-1',
        'title': 'Cached article',
        'description': 'Still useful while offline',
        'url': 'https://playvalorant.com/en-us/news/cached/',
        'category': 'news',
      },
    ]);
    await cache.setString(
      'valorant_news_feed_fetched_at',
      DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    );
    final dio = Dio()..httpClientAdapter = _FailingAdapter();

    final articles = await NewsRemoteSource(dio).fetchNews();

    expect(articles.single.title, 'Cached article');
  });

  test('evicts an invalid stale news cache', () async {
    final cache = CacheStorage.instance;
    await cache.setJson('valorant_news_feed', [
      {'title': 'Missing URL'},
    ]);
    final dio = Dio()..httpClientAdapter = _FailingAdapter();

    expect(await NewsRemoteSource(dio).fetchNews(), isEmpty);
    expect(await cache.getJsonList('valorant_news_feed'), isNull);
    expect(await cache.getString('valorant_news_feed_fetched_at'), isNull);
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('unavailable', 503);
  }

  @override
  void close({bool force = false}) {}
}

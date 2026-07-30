/// Wraps fetched data with a flag indicating whether it came from local cache.
class CachedFetchResult<T> {
  final T data;
  final bool fromCache;

  const CachedFetchResult(this.data, {this.fromCache = false});
}

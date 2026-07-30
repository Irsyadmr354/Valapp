import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/auth_dio.dart';
import '../network/api_dio.dart';
import '../network/cookie_service.dart';
import '../network/interceptors/valorant_interceptor.dart';
import '../storage/secure_storage.dart';
import '../storage/cache_storage.dart';
import '../../shared/utils/version_service.dart';
import '../../shared/utils/valorant_assets.dart';

// ── Auth & Session ─────────────────────────────────────────────────────────────

import '../../features/auth/data/auth_remote_source.dart';
import '../../features/auth/data/credentials_local_source.dart';
import '../../features/auth/domain/auth_repository.dart';

// ── Shop ───────────────────────────────────────────────────────────────────────

import '../../features/shop/data/store_remote_source.dart';
import '../../features/shop/data/store_local_cache.dart';
import '../../features/shop/domain/store_repository.dart';

// ── Match ──────────────────────────────────────────────────────────────────────

import '../../features/match/data/match_remote_source.dart';

// ── Rank ───────────────────────────────────────────────────────────────────────

import '../../features/rank/data/mmr_remote_source.dart';

// ── Contracts ─────────────────────────────────────────────────────────────────

import '../../features/contracts/data/contracts_remote_source.dart';

// ── Profile ───────────────────────────────────────────────────────────────────

import '../../features/profile/data/account_remote_source.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Core singletons
// ═════════════════════════════════════════════════════════════════════════════

final secureStorageProvider = Provider<SecureStorage>((_) => SecureStorage.instance);

final cacheStorageProvider = Provider<CacheStorage>((_) => CacheStorage.instance);

final versionServiceProvider = Provider<VersionService>((_) => VersionService.instance);

final valorantAssetsProvider = Provider<ValorantAssets>((_) => ValorantAssets.instance);

// ── Cookie jar (async init via FutureProvider) ─────────────────────────────

final cookieJarProvider = FutureProvider<PersistCookieJar>((_) => createCookieJar());

// ── Auth Dio ───────────────────────────────────────────────────────────────

final authDioProvider = FutureProvider<Dio>((ref) async {
  final jar = await ref.watch(cookieJarProvider.future);
  return createAuthDio(jar);
});

// ── Credentials local source ───────────────────────────────────────────────

final credentialsLocalSourceProvider = Provider<CredentialsLocalSource>((ref) {
  return CredentialsLocalSource(ref.watch(secureStorageProvider));
});

// ── Auth remote source ─────────────────────────────────────────────────────

final authRemoteSourceProvider = FutureProvider<AuthRemoteSource>((ref) async {
  final authDio = await ref.watch(authDioProvider.future);
  return AuthRemoteSource(authDio, Dio());
});

// ── Auth repository ────────────────────────────────────────────────────────

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final remote = await ref.watch(authRemoteSourceProvider.future);
  final local = ref.watch(credentialsLocalSourceProvider);
  return AuthRepository(remoteSource: remote, localSource: local);
});

// ── Valorant API Dio ───────────────────────────────────────────────────────

final apiDioProvider = FutureProvider<Dio>((ref) async {
  final secureStorage = ref.watch(secureStorageProvider);
  final versionService = ref.watch(versionServiceProvider);

  late AuthRepository? authRepo;

  final interceptor = ValorantInterceptor(
    secureStorage: secureStorage,
    versionService: versionService,
    onReauth: () async {
      authRepo ??= await ref.read(authRepositoryProvider.future);
      await authRepo!.reauth();
    },
    onAuthFailed: () async {
      // Clear stored credentials and signal router to redirect to login
      final local = ref.read(credentialsLocalSourceProvider);
      await local.clear();
      ref.invalidate(currentCredentialsProvider);
    },
  );

  return createApiDio(interceptor);
});

// ── Store ──────────────────────────────────────────────────────────────────

final storeRemoteSourceProvider = FutureProvider<StoreRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return StoreRemoteSource(dio);
});

final storeLocalCacheProvider = Provider<StoreLocalCache>((ref) {
  return StoreLocalCache(ref.watch(cacheStorageProvider));
});

final storeRepositoryProvider = FutureProvider<StoreRepository>((ref) async {
  final remote = await ref.watch(storeRemoteSourceProvider.future);
  final local = ref.watch(storeLocalCacheProvider);
  final assets = ref.watch(valorantAssetsProvider);
  return StoreRepository(
      remoteSource: remote, localCache: local, assets: assets);
});

// ── Match ──────────────────────────────────────────────────────────────────

final matchRemoteSourceProvider = FutureProvider<MatchRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return MatchRemoteSource(dio);
});

// ── Rank ───────────────────────────────────────────────────────────────────

final mmrRemoteSourceProvider = FutureProvider<MmrRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return MmrRemoteSource(dio);
});

// ── Contracts ─────────────────────────────────────────────────────────────

final contractsRemoteSourceProvider =
    FutureProvider<ContractsRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return ContractsRemoteSource(dio);
});

// ── Profile ───────────────────────────────────────────────────────────────

final accountRemoteSourceProvider =
    FutureProvider<AccountRemoteSource>((ref) async {
  final dio = await ref.watch(apiDioProvider.future);
  return AccountRemoteSource(dio);
});

// ── Current credentials (reactive) ────────────────────────────────────────

final currentCredentialsProvider =
    FutureProvider.autoDispose((ref) async {
  final local = ref.watch(credentialsLocalSourceProvider);
  return local.load();
});

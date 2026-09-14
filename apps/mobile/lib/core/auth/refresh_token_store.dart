/// Where the refresh token lives: the platform's secure storage (Android
/// Keystore-backed, iOS Keychain), never the database or logs. The access
/// token is kept in memory only (`AuthController`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class RefreshTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

class SecureRefreshTokenStore implements RefreshTokenStore {
  const SecureRefreshTokenStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  static const String _key = 'kunim.auth.refresh_token';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final refreshTokenStoreProvider = Provider<RefreshTokenStore>(
  (ref) => const SecureRefreshTokenStore(),
);

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? backing])
      : _backing = backing ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );
  final FlutterSecureStorage _backing;

  @override
  Future<String?> read(String key) => _backing.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _backing.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _backing.delete(key: key);
}

class FakeSecureStore implements SecureStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);
}

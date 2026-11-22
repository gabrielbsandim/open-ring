import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';

final class SecureStorageSecretStore implements SecretStore {
  const new([FlutterSecureStorage? storage])
    : _storage = storage ?? _defaultStorage;

  static const _defaultStorage = FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @visibleForTesting
  AndroidOptions get androidOptions => _storage.aOptions;

  @override
  Future<String?> read(String name) async {
    try {
      return await _storage.read(key: name);
    } on Object {
      await _deleteQuietly(name);
      return null;
    }
  }

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);

  Future<void> _deleteQuietly(String name) async {
    try {
      await _storage.delete(key: name);
    } on Object {
      // Best-effort cleanup when ciphertext cannot be unwrapped.
    }
  }
}

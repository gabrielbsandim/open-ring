const String aiApiKeySecretName = 'ai.api_key';

abstract interface class SecretStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

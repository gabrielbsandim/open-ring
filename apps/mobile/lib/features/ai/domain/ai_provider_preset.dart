/// Provider presets fill the base URL and timeout/context defaults only.
/// Models come from the provider's model list or user entry, never hardcoded.
enum AiProviderPreset {
  openAi,
  openRouter,
  groq,
  gemini,
  anthropic,
  ollama,
  lmStudio,
  custom;

  String get baseUrl => switch (this) {
    AiProviderPreset.openAi => 'https://api.openai.com/v1',
    AiProviderPreset.openRouter => 'https://openrouter.ai/api/v1',
    AiProviderPreset.groq => 'https://api.groq.com/openai/v1',
    AiProviderPreset.gemini =>
      'https://generativelanguage.googleapis.com/v1beta/openai',
    AiProviderPreset.anthropic => 'https://api.anthropic.com/v1',
    AiProviderPreset.ollama ||
    AiProviderPreset.lmStudio ||
    AiProviderPreset.custom => '',
  };

  String get placeholderUrl => switch (this) {
    AiProviderPreset.ollama => 'http://192.168.1.10:11434/v1',
    AiProviderPreset.lmStudio => 'http://192.168.1.10:1234/v1',
    _ => '',
  };

  bool get isLocal =>
      this == AiProviderPreset.ollama || this == AiProviderPreset.lmStudio;

  bool get keyRequired => switch (this) {
    AiProviderPreset.ollama ||
    AiProviderPreset.lmStudio ||
    AiProviderPreset.custom => false,
    _ => true,
  };

  int get defaultTimeoutSeconds => isLocal ? 600 : 180;

  bool get defaultCompactContext => isLocal;
}

# Local LLMs via Ollama, for offline work. See NOTES.md.

{ ... }:

{
  services.ollama = {
    enable = true;
    environmentVariables = {
      # Ollama's own default num_ctx is far too small for an agent's system
      # prompt.
      OLLAMA_CONTEXT_LENGTH = "32768";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "30m";
      # Roughly halves KV-cache memory at a negligible quality cost.
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
    # Hosts select the inference backend; the default package is CPU-only.
    loadModels = [
      "gemma4:26b-a4b-it-qat"
      "huihui_ai/gemma-4-abliterated:26b"
    ];
  };
}

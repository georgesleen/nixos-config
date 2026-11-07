# Ollama for the fizzbot bot, on the loopback address only.

{ ... }:

{
  services.ollama = {
    enable = true;
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "2048";
      # Keeps the model in memory, because a reload from the flash drive is slow.
      OLLAMA_KEEP_ALIVE = "-1";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_NUM_PARALLEL = "1";
    };
    # Stand-in until the retrained fizzbot model is on the host.
    loadModels = [ "qwen2.5:0.5b" ];
  };
  # Compressed RAM swap, so a model load does not exhaust memory.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}

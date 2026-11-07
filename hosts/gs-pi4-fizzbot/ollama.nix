# Ollama for the fizzbot bot, on the loopback address only.

{ pkgs, ... }:

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
  };
  # Loads the model at boot, so that the first reply is not a cold start.
  systemd.services.ollama-preload-fizzbot = {
    after = [ "ollama.service" ];
    path = [ pkgs.curl ];
    requires = [ "ollama.service" ];
    script = ''
      curl --fail --silent --show-error --output /dev/null \
        --retry 30 --retry-connrefused --retry-delay 2 \
        --data '{"model":"fizzbot"}' http://127.0.0.1:11434/api/generate
    '';
    serviceConfig = {
      DynamicUser = true;
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };
  # Compressed RAM swap, so a model load does not exhaust memory.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}

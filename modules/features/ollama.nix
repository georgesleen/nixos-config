# Local LLMs via Ollama, for offline work. omp discovers the server on its
# own (implicit `ollama` provider at 127.0.0.1:11434), so nothing on the omp
# side needs configuring beyond the context length in home/dotfiles/omp.nix.
#
# Sized for the Framework: 32 GB shared RAM, about 8 GB of it taken by the
# desktop. The 26B-A4B MoE (4B active) fits; the dense 31B is too slow.

{ ... }:

{
  services.ollama = {
    enable = true;
    environmentVariables = {
      # Ollama's own default num_ctx is far too small for an agent's system
      # prompt. omp reads the same variable to size its budget (omp.nix), so
      # the two must agree or omp overruns the window without noticing.
      OLLAMA_CONTEXT_LENGTH = "32768";
      OLLAMA_FLASH_ATTENTION = "1";
      # Roughly halves KV-cache memory at a negligible quality cost.
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
    # Hosts select the inference backend; the default package is CPU-only.
    # QAT: Google's quantization-aware-trained Q4, better than plain Q4 at the
    # same size. The abliterated build is a plain Q4_K (18 GB); only one model
    # is resident at a time (OLLAMA_MAX_LOADED_MODELS).
    loadModels = [
      "gemma4:26b-a4b-it-qat"
      "huihui_ai/gemma-4-abliterated:26b"
    ];
  };
}

# Local LLMs via Ollama, for offline work. omp discovers the server on its
# own (implicit `ollama` provider at 127.0.0.1:11434), so nothing on the omp
# side needs configuring beyond the context length in home/dotfiles/omp.nix.
#
# Sized for the T480s: 16 GB shared RAM, about 8 GB of it taken by the desktop.
# gemma4:e4b-it-qat is 6.1 GB; the 26B/31B variants do not fit.

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
    # Default package, CPU-only. Vulkan was tried on the UHD 620 (2026-10-12):
    # Ollama drops integrated GPUs unless OLLAMA_IGPU_ENABLE=1, and with it set
    # llama.cpp's Vulkan backend died mid-prompt with vk::DeviceLostError.
    # QAT: Google's quantization-aware-trained Q4, better than plain Q4 at the
    # same size.
    loadModels = [ "gemma4:e4b-it-qat" ];
  };
}

# ollama

## Overview

Local LLMs via Ollama, for offline work.

Sized for the Framework: 32 GB shared RAM, about 8 GB of it taken by the desktop. The 26B-A4B MoE (4B active) fits; the dense 31B is too slow.

## loadModels

Hosts select the inference backend; the default package is CPU-only. QAT: Google's quantization-aware-trained Q4, better than plain Q4 at the same size. The abliterated build is a plain Q4_K (18 GB); only one model is resident at a time (OLLAMA_MAX_LOADED_MODELS).

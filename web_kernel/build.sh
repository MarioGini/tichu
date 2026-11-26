#!/usr/bin/env bash
# Builds assets/bots/mlp_kernel.wasm from mlp_kernel.c (clang >= 16 with
# the wasm32 target and wasm-ld). The .wasm is committed, so the app build
# does not need clang.
set -euo pipefail
cd "$(dirname "$0")"
clang --target=wasm32 -O3 -msimd128 -nostdlib -ffreestanding \
  -Wl,--no-entry -Wl,--export=__heap_base -Wl,--allow-undefined \
  -o ../assets/bots/mlp_kernel.wasm mlp_kernel.c
ls -l ../assets/bots/mlp_kernel.wasm

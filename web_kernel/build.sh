#!/usr/bin/env bash
# Builds the web's play-net kernel from mlp_kernel.c into web/ (served next
# to the app, git-ignored):
#   web/mlp_kernel_relaxed.wasm  relaxed SIMD (fused multiply-add; Chrome 114+)
#   web/mlp_kernel.wasm          plain SIMD128, for browsers without it
# Needs clang and wasm-ld with the wasm32 target: the newest
# /usr/lib/llvm-*/bin/clang (CI installs the latest LLVM), or $CLANG.
#
# Flags measured in V8 (us per scoring of the v10 net): -O3 2.80,
# + LTO 2.43, + relaxed SIMD 2.32; wasm-opt -O3 on top gained nothing.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${CLANG:-}" ]]; then
  CLANG=$(ls -d /usr/lib/llvm-*/bin/clang 2>/dev/null | sort -V | tail -1)
  CLANG=${CLANG:-clang}
fi
"$CLANG" --version | head -1
flags=(
  --target=wasm32 -O3 -flto -msimd128 -nostdlib -ffreestanding
  -Wl,--no-entry -Wl,--export=__heap_base -Wl,--lto-O3 -Wl,-O3
  -Wl,--strip-all
)
"$CLANG" "${flags[@]}" -mrelaxed-simd -o ../web/mlp_kernel_relaxed.wasm \
  mlp_kernel.c
"$CLANG" "${flags[@]}" -o ../web/mlp_kernel.wasm mlp_kernel.c
ls -l ../web/mlp_kernel*.wasm

// Prefix scorer of the play net for the web build: the same computation as
// MlpSimdPrefixScorer (lib/agents/nn/mlp.dart) on WebAssembly SIMD
// (f32x4), which Chrome runs as NEON / SSE. dart2js has no float32 SIMD
// (Float32x4 is emulated) and dart2wasm does not map Float32x4 to wasm
// SIMD, so the hot loop lives here. Build: web_kernel/build.sh.
//
// Layout per layer l (in -> out units): weights column-major, every input
// row padded to vec(l) = ceil(out / 4) vectors: w[l][i * vec(l) + v].
#include <wasm_simd128.h>

// a + b * c: one fused instruction with relaxed SIMD (-mrelaxed-simd;
// Chrome 114+), a multiply and an add otherwise.
#ifdef __wasm_relaxed_simd__
#define MADD(a, b, c) wasm_f32x4_relaxed_madd(b, c, a)
#else
#define MADD(a, b, c) wasm_f32x4_add(a, wasm_f32x4_mul(b, c))
#endif

#define MAX_LAYERS 8

extern unsigned char __heap_base;
static unsigned long heap_top = 0;

// Bump allocator (16-byte aligned); memory is never freed. Grows the
// memory as needed.
__attribute__((export_name("kalloc"))) void *kalloc(int bytes) {
  if (heap_top == 0) heap_top = (unsigned long)&__heap_base;
  heap_top = (heap_top + 15) & ~15UL;
  unsigned long p = heap_top;
  heap_top += (unsigned long)bytes;
  unsigned long pages = __builtin_wasm_memory_size(0);
  if (heap_top > pages * 65536) {
    unsigned long need = (heap_top - pages * 65536 + 65535) / 65536;
    if (__builtin_wasm_memory_grow(0, need) == (unsigned long)-1) return 0;
  }
  return (void *)p;
}

typedef struct {
  int layers;               // linear layers
  int sizes[MAX_LAYERS + 1];
  int vec[MAX_LAYERS];      // output vectors per layer
  v128_t *w[MAX_LAYERS];
  v128_t *b[MAX_LAYERS];
  v128_t *base;             // layer-0 pre-activation of the prefix
  v128_t *act[MAX_LAYERS];  // layer outputs
  int *rows;                // non-zero inputs: weight row offsets
  v128_t *xs;               // ... and their values, splatted
  float *input;             // prefix or suffix features, written by Dart
} Net;

__attribute__((export_name("net_new"))) Net *net_new(int layers, int s0,
    int s1, int s2, int s3, int s4, int s5, int s6, int s7, int s8) {
  int sizes[MAX_LAYERS + 1] = {s0, s1, s2, s3, s4, s5, s6, s7, s8};
  if (layers < 1 || layers > MAX_LAYERS) return 0;
  Net *n = kalloc(sizeof(Net));
  n->layers = layers;
  int widest = 0;
  for (int l = 0; l <= layers; l++) {
    n->sizes[l] = sizes[l];
    if (sizes[l] > widest) widest = sizes[l];
  }
  for (int l = 0; l < layers; l++) {
    int v = (sizes[l + 1] + 3) / 4;
    n->vec[l] = v;
    n->w[l] = kalloc(sizes[l] * v * 16);
    n->b[l] = kalloc(v * 16);
    n->act[l] = kalloc(v * 16);
  }
  n->base = kalloc(n->vec[0] * 16);
  n->rows = kalloc(widest * 4);
  n->xs = kalloc(widest * 16);
  n->input = kalloc(widest * 4);
  return n;
}

__attribute__((export_name("net_weights"))) float *net_weights(Net *n, int l) {
  return (float *)n->w[l];
}

__attribute__((export_name("net_bias"))) float *net_bias(Net *n, int l) {
  return (float *)n->b[l];
}

__attribute__((export_name("net_input"))) float *net_input(Net *n) {
  return n->input;
}

// out[v] = init[v] + sum_k w[rows[k] + v] * xs[k], k in input order.
static void accumulate(v128_t *out, const v128_t *init, const v128_t *w,
                       const int *rows, const v128_t *xs, int n, int len) {
  int v = 0;
  for (; v + 8 <= len; v += 8) {
    v128_t a0 = init[v], a1 = init[v + 1], a2 = init[v + 2], a3 = init[v + 3];
    v128_t a4 = init[v + 4], a5 = init[v + 5], a6 = init[v + 6],
           a7 = init[v + 7];
    for (int k = 0; k < n; k++) {
      const v128_t x = xs[k];
      const v128_t *r = w + rows[k] + v;
      a0 = MADD(a0, r[0], x);
      a1 = MADD(a1, r[1], x);
      a2 = MADD(a2, r[2], x);
      a3 = MADD(a3, r[3], x);
      a4 = MADD(a4, r[4], x);
      a5 = MADD(a5, r[5], x);
      a6 = MADD(a6, r[6], x);
      a7 = MADD(a7, r[7], x);
    }
    out[v] = a0; out[v + 1] = a1; out[v + 2] = a2; out[v + 3] = a3;
    out[v + 4] = a4; out[v + 5] = a5; out[v + 6] = a6; out[v + 7] = a7;
  }
  for (; v < len; v++) {
    v128_t a = init[v];
    for (int k = 0; k < n; k++) {
      a = MADD(a, w[rows[k] + v], xs[k]);
    }
    out[v] = a;
  }
}

// Layer-0 contribution of the prefix (input[0 .. prefix_len)).
__attribute__((export_name("net_set_prefix"))) void net_set_prefix(
    Net *n, int prefix_len) {
  int vec = n->vec[0];
  int k = 0;
  for (int i = 0; i < prefix_len; i++) {
    float x = n->input[i];
    if (x == 0) continue;
    n->rows[k] = i * vec;
    n->xs[k] = wasm_f32x4_splat(x);
    k++;
  }
  accumulate(n->base, n->b[0], n->w[0], n->rows, n->xs, k, vec);
}

// Output (first unit) for the prefix followed by the suffix
// input[0 .. suffix_len), which are inputs prefix_len + i.
__attribute__((export_name("net_score"))) float net_score(
    Net *n, int prefix_len, int suffix_len) {
  int vec = n->vec[0];
  int k = 0;
  for (int i = 0; i < suffix_len; i++) {
    float x = n->input[i];
    if (x == 0) continue;
    n->rows[k] = (prefix_len + i) * vec;
    n->xs[k] = wasm_f32x4_splat(x);
    k++;
  }
  accumulate(n->act[0], n->base, n->w[0], n->rows, n->xs, k, vec);
  for (int l = 1; l < n->layers; l++) {
    const float *cur = (const float *)n->act[l - 1];
    int next = n->vec[l];
    int in_len = n->sizes[l];
    k = 0;
    for (int i = 0; i < in_len; i++) {
      float x = cur[i];
      if (x <= 0) continue;  // ReLU
      n->rows[k] = i * next;
      n->xs[k] = wasm_f32x4_splat(x);
      k++;
    }
    accumulate(n->act[l], n->b[l], n->w[l], n->rows, n->xs, k, next);
  }
  return ((const float *)n->act[n->layers - 1])[0];
}

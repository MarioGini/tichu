// Checks web kernels (web_kernel/build.sh) against a plain JavaScript
// forward pass of a random net shaped like the play net, and times them:
//   node web_kernel/check.mjs web/mlp_kernel_relaxed.wasm web/mlp_kernel.wasm
// Exits non-zero when a kernel's output is off (beyond float32 rounding).
import fs from 'fs';

const sizes = [431, 256, 128, 64, 1];
const layers = sizes.length - 1;
const prefix = 373;
let seed = 1;
const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648 - 0.5;
const W = [];
const B = [];
for (let l = 0; l < layers; l++) {
  W.push(Array.from({ length: sizes[l + 1] * sizes[l] }, () => rnd() * 0.2));
  B.push(Array.from({ length: sizes[l + 1] }, () => rnd() * 0.1));
}
const x = Array.from({ length: sizes[0] }, () => (rnd() < -0.25 ? rnd() + 0.5 : 0));

let a = x;
for (let l = 0; l < layers; l++) {
  const out = [];
  for (let j = 0; j < sizes[l + 1]; j++) {
    let s = B[l][j];
    for (let i = 0; i < sizes[l]; i++) s += W[l][j * sizes[l] + i] * a[i];
    out.push(l < layers - 1 ? Math.max(0, s) : s);
  }
  a = out;
}
const reference = a[0];

let failed = false;
for (const file of process.argv.slice(2)) {
  if (!WebAssembly.validate(fs.readFileSync(file))) {
    console.log(`${file}: not supported by this runtime, skipped`);
    continue;
  }
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(file), {});
  const e = instance.exports;
  const net = e.net_new(layers, ...sizes, ...Array(9 - sizes.length).fill(0));
  for (let l = 0; l < layers; l++) {
    const inLen = sizes[l];
    const out = sizes[l + 1];
    const vec = Math.ceil(out / 4);
    const w = new Float32Array(e.memory.buffer, e.net_weights(net, l), inLen * vec * 4);
    for (let j = 0; j < out; j++) for (let i = 0; i < inLen; i++) w[i * vec * 4 + j] = W[l][j * inLen + i];
    const b = new Float32Array(e.memory.buffer, e.net_bias(net, l), vec * 4);
    for (let j = 0; j < out; j++) b[j] = B[l][j];
  }
  const input = new Float32Array(e.memory.buffer, e.net_input(net), sizes[0]);
  input.set(x.slice(0, prefix));
  e.net_set_prefix(net, prefix);
  input.set(x.slice(prefix));
  const got = e.net_score(net, prefix, sizes[0] - prefix);
  const ok = Math.abs(got - reference) <= 1e-4 * Math.max(1, Math.abs(reference));
  failed ||= !ok;
  const times = [];
  for (let rep = 0; rep < 5; rep++) {
    const t = performance.now();
    for (let r = 0; r < 50000; r++) e.net_score(net, prefix, sizes[0] - prefix);
    times.push(((performance.now() - t) / 50000) * 1000);
  }
  console.log(
    `${file}: ${ok ? 'ok' : 'WRONG'} (${got} vs ${reference}), ` +
      `${Math.min(...times).toFixed(3)} us per scoring (best of 5)`,
  );
}
process.exit(failed ? 1 : 0);

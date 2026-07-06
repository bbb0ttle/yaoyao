import { type ZCanvasExports } from './types'

async function init() {
  const canvas = document.getElementById("canvas") as HTMLCanvasElement;
  const ctx = canvas.getContext("2d")!;

  const response = await fetch("/z-canvas.wasm");
  const wasmBytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(wasmBytes, {
    env: {},
  });

  const wasm = instance.exports as ZCanvasExports;
  wasm.init();

  let pixelArray: Uint8ClampedArray<ArrayBuffer>; 
  let imageData: ImageData;

  function getCSSSize() {
    const rect = canvas.getBoundingClientRect();
    return { w: Math.max(1, rect.width), h: Math.max(1, rect.height) };
  }

  function resizeToDevice() {
    const dpr = window.devicePixelRatio || 1;
    const { w: cssW, h: cssH } = getCSSSize();
    const w = Math.max(1, Math.floor(cssW * dpr));
    const h = Math.max(1, Math.floor(cssH * dpr));

    const maxDim = 4096;
    const cw = Math.min(w, maxDim);
    const ch = Math.min(h, maxDim);

    canvas.width = cw;
    canvas.height = ch;

    wasm.resize(cw, ch);

    const ptr = wasm.get_framebuffer_ptr();
    if (ptr === 0) return;
    const len = cw * ch * 4;
    const buffer = wasm.memory.buffer as ArrayBuffer;
    pixelArray = new Uint8ClampedArray(buffer, ptr, len) as Uint8ClampedArray<ArrayBuffer>;
    imageData = new ImageData(pixelArray, cw, ch);
    ctx.putImageData(imageData, 0, 0);
  }

  let start = performance.now();

  resizeToDevice();

  let resizeRaf = 0;
  window.addEventListener("resize", () => {
    if (resizeRaf) cancelAnimationFrame(resizeRaf);
    resizeRaf = requestAnimationFrame(() => {
      resizeToDevice();
      resizeRaf = 0;
    });
  });

  canvas.addEventListener("click", (e: MouseEvent) => {
    wasm.show_meteor_shower(wasm.get_width() / 3, wasm.get_height());
  });

  function loop(_now: number) {
    const elapsed = (performance.now() - start) / 1000;
    wasm.update_frame(elapsed, Date.now(), window.devicePixelRatio || 1);
    ctx.putImageData(imageData, 0, 0);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}

init();

interface ZCanvasExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  init(): void;
  get_framebuffer_ptr(): number;
  get_width(): number;
  get_height(): number;
  resize(w: number, h: number): void;
  update_frame(elapsed: number, unix_ms: number, dpr: number): void;
  handle_click(x: number, y: number): void;
}

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

  let pixelArray: Uint8ClampedArray;
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
    pixelArray = new Uint8ClampedArray(wasm.memory.buffer, ptr, len);
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
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const x = (e.clientX - rect.left) * dpr;
    const y = (e.clientY - rect.top) * dpr;
    wasm.handle_click(x, y);
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

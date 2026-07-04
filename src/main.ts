interface ZCanvasExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  get_framebuffer_ptr(): number;
  get_width(): number;
  get_height(): number;
  resize(w: number, h: number): void;
  set_mouse(x: number, y: number, on_canvas: number): void;
  update_frame(time: number): void;
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

    const elapsed = (performance.now() - start) / 1000;
    wasm.update_frame(elapsed);
    ctx.putImageData(imageData, 0, 0);
  }

  // mouse tracking for custom cursor
  let mouseX = 0;
  let mouseY = 0;
  let mouseOnCanvas = false;

  canvas.addEventListener("mousemove", (e) => {
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    mouseX = Math.round((e.clientX - rect.left) * scaleX);
    mouseY = Math.round((e.clientY - rect.top) * scaleY);
    mouseOnCanvas = true;
  });

  canvas.addEventListener("mouseleave", () => {
    mouseOnCanvas = false;
  });

  let start = performance.now();

  // initial size and listener
  resizeToDevice();

  let resizeRaf = 0;
  window.addEventListener("resize", () => {
    if (resizeRaf) cancelAnimationFrame(resizeRaf);
    resizeRaf = requestAnimationFrame(() => {
      resizeToDevice();
      resizeRaf = 0;
    });
  });

  function loop(now: number) {
    const elapsed = (now - start) / 1000;
    wasm.set_mouse(mouseX, mouseY, mouseOnCanvas ? 1 : 0);
    wasm.update_frame(elapsed);
    ctx.putImageData(imageData, 0, 0);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}

init();

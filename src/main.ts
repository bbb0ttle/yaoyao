interface ZCanvasExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  get_framebuffer_ptr(): number;
  get_width(): number;
  get_height(): number;
  resize(w: number, h: number): void;
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
    mouseX = (e.clientX - rect.left) * scaleX;
    mouseY = (e.clientY - rect.top) * scaleY;
    mouseOnCanvas = true;
  });

  canvas.addEventListener("mouseleave", () => {
    mouseOnCanvas = false;
  });

  function drawWand(ctx: CanvasRenderingContext2D, x: number, y: number) {
    const angle = (35 * Math.PI) / 180; // ~35° from vertical
    const shaftLen = 90;
    const dx = Math.sin(angle) * shaftLen;
    const dy = Math.cos(angle) * shaftLen;
    const bx = x + dx;
    const by = y + dy;

    // shaft
    ctx.save();
    ctx.strokeStyle = "rgba(40, 40, 40, 0.85)";
    ctx.lineWidth = 2;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(bx, by);
    ctx.stroke();

    // tip glow
    ctx.fillStyle = "rgba(200, 160, 60, 0.9)";
    ctx.beginPath();
    ctx.arc(x, y, 3, 0, Math.PI * 2);
    ctx.fill();

    // sparkle cross
    ctx.strokeStyle = "rgba(220, 200, 140, 0.8)";
    ctx.lineWidth = 1;
    const sparkleR = 6;
    ctx.beginPath();
    ctx.moveTo(x - sparkleR, y);
    ctx.lineTo(x + sparkleR, y);
    ctx.moveTo(x, y - sparkleR);
    ctx.lineTo(x, y + sparkleR);
    ctx.stroke();
    ctx.restore();
  }

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
    wasm.update_frame(elapsed);
    ctx.putImageData(imageData, 0, 0);
    if (mouseOnCanvas) drawWand(ctx, mouseX, mouseY);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}

init();

interface ZCanvasExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  get_framebuffer_ptr(): number;
  get_width(): number;
  get_height(): number;
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

  const width = wasm.get_width();
  const height = wasm.get_height();
  const ptr = wasm.get_framebuffer_ptr();

  const pixelArray = new Uint8ClampedArray(
    wasm.memory.buffer,
    ptr,
    width * height * 4,
  );

  const imageData = new ImageData(pixelArray, width, height);

  let start = performance.now();

  function loop(now: number) {
    const elapsed = (now - start) / 1000;
    wasm.update_frame(elapsed);
    ctx.putImageData(imageData, 0, 0);
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
}

init();

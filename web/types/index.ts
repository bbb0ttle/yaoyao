export interface ZCanvasExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  init(): void;
  get_framebuffer_ptr(): number;
  get_width(): number;
  get_height(): number;
  resize(w: number, h: number): void;
  update_frame(elapsed: number, unix_ms: number, dpr: number): void;
  show_meteor_shower(x: number, y: number): void;
}
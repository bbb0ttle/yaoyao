/** Emscripten Module interface for oayao WASM */
export interface OayaoModule {
  onRuntimeInitialized?: () => void;
  calledRun: boolean;
  _trigger_meteor_shower(x: number, y: number): void;
  canvas?: HTMLCanvasElement;
}

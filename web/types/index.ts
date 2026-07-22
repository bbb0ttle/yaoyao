/** Emscripten Module interface for oayao WASM */
export interface OayaoModule {
  onRuntimeInitialized?: () => void;
  calledRun: boolean;
  _trigger_meteor_shower(x: number, y: number): void;
  _oayao_set_days_counter_start_ms(ms: number): void;
  canvas?: HTMLCanvasElement;
}

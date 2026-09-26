import { showForcastUI } from './forcast';
import type { OayaoModule } from './types';

async function init() {
  const Module: OayaoModule = await (window as any).wasmReady;

  // Emscripten fires onRuntimeInitialized (which resolves wasmReady) before
  // main(), and sokol only calls the Zig init callback on the first frame —
  // wait for that frame before calling into the app, or the call is dropped.
  await new Promise<void>((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  );

  // 2022-08-17 at local midnight — same semantics as iOS
  // (Calendar.current.startOfDay), so both ends show the same count.
  Module._oayao_set_days_counter_start_ms(new Date(2022, 7, 17).getTime());

  const canvas = document.querySelector('canvas');
  if (!canvas) {
    console.error('No canvas element found; sokol may not have initialized correctly.');
    return;
  }

  showForcastUI('forecast', () => {
    const x = canvas.width / 3;
    const y = canvas.height;
    Module._trigger_meteor_shower(x, y);
  });
}

init().catch(console.error);

import { showForcastUI } from './forcast';
import type { OayaoModule } from './types';

async function init() {
  const Module: OayaoModule = await (window as any).wasmReady;

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

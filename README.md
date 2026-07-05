# z-canvas

A Zig + WASM canvas animation featuring particle-based heart rendering, meteor click effects, and a days counter. Renders via software rasterization into a shared memory buffer consumed by a TypeScript web frontend.

## Prerequisites

- [Zig](https://ziglang.org/) >= 0.17.0
- [Node.js](https://nodejs.org/) and [pnpm](https://pnpm.io/)

## Build & Run

```sh
# Build the WASM module
zig build wasm

# Install frontend dependencies
pnpm install

# Start the dev server
pnpm dev
```

The WASM output is written to `zig-out/public/z-canvas.wasm`.

## Project Structure

```
src/
  main.zig          WASM entry point (exported functions)
  app.zig           Public API re-exports
  Canvas.zig        Pixel buffer ownership and lifecycle
  FrameBuffer.zig   Software rasterizer (pixel ops, polygon fill, font)
  HeartSystem.zig   Particle-based heart animation
  MeteorSystem.zig  Click-activated meteor particle system
  Particle.zig      Global particle pool allocator
  random.zig        Minimal LCG PRNG
  core/
    business.zig    Domain types (Rgba, Vec2), heart math, bitmap font
web/
  index.html, main.ts, style.css   TypeScript frontend
public/
  z-canvas.wasm    Build output (served by Vite)
```

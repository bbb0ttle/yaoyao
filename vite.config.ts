import { defineConfig, type Plugin } from "vite";
import { exec } from "child_process";
import { copyFileSync, mkdirSync } from "fs";

function zigWatchPlugin(): Plugin {
  return {
    name: "zig-watch",
    configureServer(server) {
      function build() {
        exec("zig build web -Dtarget=wasm32-emscripten", (err, _stdout, stderr) => {
          if (err) {
            console.error("[zig-watch] zig build failed:\n", stderr);
            return;
          }
          try {
            mkdirSync("web/public", { recursive: true });
            copyFileSync("zig-out/web/oayao.js", "web/public/oayao.js");
            copyFileSync("zig-out/web/oayao.wasm", "web/public/oayao.wasm");
            console.log("[zig-watch] copied emscripten output to web/public/");
          } catch (e) {
            console.error("[zig-watch] failed to copy:", e);
          }
        });
      }
      build();
      server.watcher.add("src");
      server.watcher.on("change", (path) => {
        if (path.endsWith(".zig")) {
          console.log(`[zig-watch] ${path} changed, rebuilding...`);
          build();
        }
      });
    },
  };
}

export default defineConfig({
  root: "web",
  publicDir: "public",
  build: {
    outDir: "../dist",
  },
  plugins: [zigWatchPlugin()],
});

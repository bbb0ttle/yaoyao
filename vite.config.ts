import { defineConfig, type Plugin } from "vite";
import { exec } from "child_process";

function zigWatchPlugin(): Plugin {
  return {
    name: "zig-watch",
    configureServer(server) {
      function build() {
        exec("zig build wasm", (err: any, _stdout: any, stderr: any) => {
          if (err) console.error("[zig-watch] build failed:\n", stderr);
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
  root: 'web',
  publicDir: '../public',
  build: {
    outDir: '../dist',
  },
  plugins: [zigWatchPlugin()],
});

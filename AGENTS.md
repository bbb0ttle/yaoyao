# AGENTS.md

协作者入口：先给命令，再给禁忌。工程细则一律以《项目编码与工程规范.md》为准。

## 命令

```bash
zig build test                                   # 单元测试（全量）
zig build test -Dtest-filter="pool"              # 过滤测试（推荐日常使用）
zig build fmt                                    # 格式检查（提交前必过）
zig build run                                    # 桌面运行
zig build -Dtarget=aarch64-ios                   # iOS 静态库
zig build -Dtarget=aarch64-ios ios-app           # iOS .app 包
source zig-pkg/N-V-*/emsdk_env.sh                # web 构建前置（emsdk 环境）
zig build -Dtarget=wasm32-emscripten web         # web wasm 构建
```

## 结构

- `src/app.zig` — 应用核心编排（粒子、飞入心、主题、计数器）
- `src/build/` — 构建包（`ios.zig` / `sokol.zig`),`build.zig` 只做编排
- `test/manual_checklist.md` — 视觉/手感回归清单，**动画或渲染改动后必须逐项人工验证**
- `ios/` — Swift 壳与资源；`web/` — wasm 壳与 TS 调用方
- `scripts/` - 脚本

## 禁忌与陷阱

- 测试二进制不得向 stderr 写日志（Zig 0.17-dev 构建运行器会误判失败）；运行期日志用 `if (!builtin.is_test)` 门控
- C ABI 导出一律 `oayao_` 前缀；`trigger_meteor_shower` 是 web 遗留名，**勿删勿改**(`web/main.ts` 依赖）
- 改/删任何导出名前，先查 `web/main.ts` 与 `ios/` 的调用方
- 动画常量均为 per-frame 单位（60fps 假设），改曲线先读 `src/app.zig` 顶部常量注释
- `src/shaders/particle.glsl.zig` 是构建生成物，提交入库但**禁止手改**，改 `particle.glsl` 后重新构建
- 粒子池容量 5000(`POOL_CAPACITY`)，池耗尽会回收最老非 immortal 粒子并告警
- 平台业务代码一定不能入侵 src 下

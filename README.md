# oayao

基于 [Zig](https://ziglang.org/) 与 [sokol](https://github.com/floooh/sokol-zig) 的心跳画布应用,运行于 macOS、iOS 与 Web 三端。

画布以薄荷绿为背景,渲染一颗呼吸跳动的白色爱心轮廓、成对漂浮的粒子、一个精确到 10 位小数的实时天数计数器,点击/触摸时触发流星雨效果。在 iOS 上,应用通过 EventKit 与系统日历集成:日历中的每个事件对应画布中一颗飞入的爱心,点击爱心即可查看事件详情。Web 版部署于 GitHub Pages(yaoyao.bbki.ng)。

## 功能特性

### 画布核心(Zig)

- 30 个点构成的呼吸爱心轮廓,正弦驱动的缩放动画;运动模式可在「跳动」(exp(sin) 快速脉冲,约 0.67s/周期)与「呼吸」(exp(sin) 慢速起伏,4s/周期,透明度随同升降)之间切换,整体尺寸、透明度与垂直位置可调
- 成对漂浮的永生粒子,伴随天数计数器
- 天数计数器(`N.NNNNNNNNNN DAYS`,3x5 点阵字体逐像素实例化渲染),起始时间戳可由宿主层设置
- 点击空白处触发流星雨与粒子爆发
- 主题系统:内置薄荷绿(Mint)、蜜桃粉(Peach)与自定义(Custom)三套配色;自定义主题的各关键颜色(背景、爱心填充/描边、计数文字)可由用户调整,切换与调整时所有颜色以 smoothstep 缓动渐变过渡
- 标记爱心(tagged hearts):由宿主层按事件 ID 生成,以流星形式飞入画布中下部星域落位(成簇生长与自由散布混合,疏密有致如星空),随后进入漂浮/跳动状态;新心心落位时旧心心按比例收缩(下限保底),近大远小、最新事件最醒目;飞入途中每次接触大心心轮廓都会触发一次与自身轨迹平行、指向同一落点的流星雨(减速变淡、尾随其后,落点始终清晰);点击命中时按最近心心回调通知宿主层;事件消失时淡出

### iOS(Swift / SwiftUI + EventKit)

- 日历同步:按设置中的日历名解析规范日历,当天每个事件生成一颗爱心,日历变更时自动重同步
- 添加事件:右下角玻璃质感悬浮按钮弹出添加表单
- 事件详情:点击画布中的爱心弹出详情表单,展示标题、日期、备注;己方事件可编辑标题/日期/备注(防抖自动保存、实时生效)并删除(对方组织的事件与只读日历为只读,不显示删除按钮)
- 设置:配置日历名称、天数计数器起始日期、画布主题、大心心行为(尺寸/透明度/运动模式/垂直位置)与界面语言(默认跟随系统,可切换 English/中文)
- 日历共享:设置页提供分步引导,通过 `calshow:` 深链跳转日历 App 完成 iCloud 共享邀请;日历优先创建于 iCloud 源(本地日历无法共享)
- 天数计数器锚定:起始日期以 `yyyy-MM-dd` 存入名为「开始的地方」的全天标记事件 notes,随 iCloud 共享同步给对方;事件本体日期保持近期并定期重拷,以避开 EventKit 4 年谓词窗口;删除该事件则回退到内置默认值,UserDefaults 仅作本地缓存

### Web(Vite + TypeScript)

- DOM 覆盖层提供流星雨触发按钮,调用 WASM 导出的 `_trigger_meteor_shower`
- 开发时 Zig 源码变更自动重新编译 WASM 并热更新
- GitHub Actions 自动构建并部署至 GitHub Pages

## 环境要求

- **Zig** 0.14.0 或更高版本([下载](https://ziglang.org/download/))
- **Xcode**(仅 iOS 构建需要,提供 iOS SDK 与模拟器)
- **Node.js** 22 与 **pnpm** 9(仅 Web 开发流程需要)
- **Emscripten** — 由构建系统自动下载,无需手动安装

## 快速开始

```bash
# macOS 桌面:编译并运行
./scripts/build-desktop.sh

# iOS 模拟器:编译、打包、安装并启动(默认 iPhone 17)
./scripts/build-ios.sh

# iOS 模拟器(可选设备/跳过构建)
./scripts/preview-ios.sh --device "iPhone 16" --no-build

# Web 开发(Vite 开发服务器,推荐)
pnpm install && pnpm dev

# Web(原始 emscripten shell,无 DOM 覆盖层)
./scripts/build-web.sh

# TestFlight 上传
./scripts/upload-testflight.sh
```

## 构建与运行

### macOS 桌面

```bash
zig build          # 编译
zig build run      # 编译并运行
```

### iOS 模拟器

```bash
zig build -Dtarget=aarch64-ios-simulator         # 编译静态库
zig build ios-app -Dtarget=aarch64-ios-simulator # 创建 .app bundle(编译 Swift 层、处理资源)
# 安装并启动:
xcrun simctl boot "iPhone 17"                              # 启动模拟器(如未启动)
xcrun simctl install booted zig-out/Oayao.app              # 安装
xcrun simctl launch booted com.bbking.oayao                # 启动
```

Intel Mac 请使用 `-Dtarget=x86_64-ios-simulator`。

`preview-ios.sh` 支持 `--device <名称>`(或环境变量 `PREVIEW_DEVICE`)指定目标模拟器,以及 `--no-build` 复用已有的 `zig-out/Oayao.app`。

### iOS 真机

```bash
zig build -Dtarget=aarch64-ios
zig build ios-app -Dtarget=aarch64-ios
```

`.app` bundle 输出至 `zig-out/Oayao.app`,使用 Xcode 安装到设备。

### TestFlight 上传

```bash
# 配置凭证(见下文"环境变量")
export APP_STORE_KEY_ID=XXXXXXXXXX
export APP_STORE_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 构建、签名、打包、验证并上传
./scripts/upload-testflight.sh
```

脚本需要 App Store Connect API key,`.p8` 文件默认位于 `~/.private_keys/AuthKey_<KEY_ID>.p8`。应用须以 `Apple Distribution` 证书签名并内嵌 provisioning profile。

手动步骤:

```bash
zig build -Dtarget=aarch64-ios                    # 编译
zig build ios-app -Dtarget=aarch64-ios            # 创建 .app bundle
codesign --force --sign "Apple Distribution" \
  zig-out/Oayao.app                               # 签名
cp profile.mobileprovision \
  zig-out/Oayao.app/embedded.mobileprovision      # 内嵌 profile
# 打包并上传:
mkdir -p Payload && cp -R zig-out/Oayao.app Payload/
zip -r Oayao.ipa Payload
xcrun altool --upload-package Oayao.ipa \
  --api-key "$APP_STORE_KEY_ID" \
  --api-issuer "$APP_STORE_ISSUER_ID" \
  --wait
```

### Web

```bash
pnpm install        # 安装依赖
pnpm dev            # Vite 开发服务器;zigWatchPlugin 监听 .zig 变更自动重编译 WASM
pnpm build          # 构建 WASM + 前端,产出至 dist/
pnpm preview        # 预览构建产物
```

`pnpm build:zig` 单独执行 WASM 构建并将 `oayao.js` / `oayao.wasm` 拷贝至 `web/public/`。`./scripts/build-web.sh` 使用原始 emscripten shell(`web/shell.html`)直接运行,不包含 Vite 覆盖层。

### 测试

```bash
zig build test      # 运行全部单元测试(src/tests.zig 及各 *_test.zig)
```

## 项目结构

```
z-canvas/
  build.zig              # 构建系统(macOS / iOS / Web / 测试)
  build.zig.zon          # 依赖声明(sokol、sokol-tools-bin、emsdk)
  package.json           # Web 前端脚本(Vite 流程)
  vite.config.ts         # Vite 配置 + zigWatchPlugin
  .env.example           # TestFlight / 签名环境变量模板
  src/
    main.zig             # sokol 入口(init/frame/event/cleanup)+ oayao_* C ABI 导出
    app.zig              # App 编排:粒子池、爱心/流星系统、标记爱心、点击处理
    random.zig           # LCG 伪随机数生成器
    tests.zig            # 测试入口
    core/
      types.zig          # Rgba、Vec2
      theme.zig          # 主题配色定义与渐变过渡状态机
      math.zig           # 心形参数曲线、呼吸/缩放动画
      font.zig           # 3x5 点阵位图字体(数字与 DAYS 相关字符)
    particles/
      particle.zig       # Particle 结构与标志位(漂浮/跳动/流星/淡出等)
      pool.zig           # 粒子池(空闲链表分配,容量 5000)
    graphics/
      gpu_state.zig      # sokol 渲染管线与实例缓冲(10k 实例,单次实例化绘制)
      text_renderer.zig  # 计数器文字 → 字形像素实例
    systems/
      heart_system.zig   # 爱心轮廓与漂浮粒子对
      meteor_system.zig  # 流星雨与拖尾粒子
    platform/
      backend.zig        # GPU 后端探测
      bootstrap.zig      # iOS Swift 宿主引导调用
    shaders/
      particle.glsl      # 统一实例着色器(shape 选择:圆点/爱心/文字像素)
      particle.glsl.zig  # sokol-shdc 生成的 Zig 绑定(勿手改)
  ios/
    Info.plist           # bundle 元数据(含日历权限说明,最低系统 15.0)
    Oayao.entitlements   # 签名 entitlements
    Oayao/
      Bridge.h               # Swift ↔ Zig C API 声明
      CallbackBridge.swift   # 引导、Sheet 呈现、悬浮按钮
      CalendarManager.swift  # EventKit 封装(日历解析、同步、CRUD)
      AddEventSheet.swift    # 添加事件表单
      EventDetailSheet.swift # 事件详情表单
      SettingsSheet.swift    # 设置界面
      SettingsStore.swift    # 设置持久化
      Localization.swift     # 应用内多语言(跟随系统 / English / 中文)
      Assets.xcassets/       # AppIcon、AccentColor、SettingsIcon
      LaunchScreen.storyboard
      PrivacyInfo.xcprivacy
  web/
    shell.html           # 原始 emscripten shell
    index.html           # Vite 入口(加载 /oayao.js,暴露 window.wasmReady)
    main.ts              # 覆盖层入口
    style.css
    forcast/             # 流星雨按钮 UI(调用 _trigger_meteor_shower)
    types/               # WASM Module 类型声明
    public/              # 构建产物 oayao.js / oayao.wasm
  scripts/
    build-desktop.sh     # 一键:macOS 构建 + 运行
    build-ios.sh         # 一键:iOS 模拟器构建 + 安装 + 启动
    preview-ios.sh       # 一键:模拟器预览(可选设备、可跳过构建)
    build-web.sh         # 一键:Web 构建 + 浏览器运行(原始 shell)
    upload-testflight.sh # 一键:构建 + 签名 + 打包 + 上传 TestFlight
  .github/workflows/
    gh-pages.yml         # push 到 iOS 分支 → 构建 → 部署 GitHub Pages
```

## iOS 架构(Swift ↔ Zig)

Zig 渲染层与 Swift 宿主层通过 C ABI 双向通信。

**引导流程**:Zig 初始化时调用 `oayao_swift_bootstrap`(见 `src/platform/bootstrap.zig` 与 `ios/Oayao/CallbackBridge.swift`),后者在主线程注册心跳点击回调、请求日历权限、添加悬浮按钮,并预热 SwiftUI 视图缓存以避免首次弹出时卡顿渲染循环。

**Zig 导出的 C API**(`ios/Oayao/Bridge.h`,实现见 `src/main.zig`):

| 函数 | 用途 |
|---|---|
| `oayao_spawn_heart(event_id)` | 为日历事件生成一颗永生漂浮爱心(流星飞入动画) |
| `oayao_remove_heart(event_id)` | 移除事件对应的爱心 |
| `oayao_sync_hearts(active_ids)` | 按换行分隔的事件 ID 列表同步;不在列表中的爱心开始淡出 |
| `oayao_set_heart_tap_callback(cb)` | 注册爱心点击回调,回调参数为事件 ID |
| `oayao_set_days_counter_start_ms(ms)` | 设置天数计数器起始时间戳(Unix epoch 毫秒) |
| `oayao_days_counter_default_start_ms()` | 内置默认起始时间戳(未设置起始日期时回退使用) |
| `oayao_transition_to_theme(theme_id)` | 切换画布主题(0=薄荷,1=蜜桃粉,2=自定义),颜色渐变过渡;未知 id 忽略 |
| `oayao_set_custom_theme_color(role, r, g, b)` | 更新自定义主题的单个颜色(role:0=背景,1=爱心填充,2=描边,3=计数文字);自定义主题激活时即时渐变生效 |
| `oayao_set_heart_opacity(opacity)` | 设置大心心透明度(0.0–1.0,自动钳制) |
| `oayao_set_heart_size_scale(size_scale)` | 设置大心心整体尺寸倍率(0.3–3.0 钳制,默认 1.0);任意尺寸下自动保持水平居中 |
| `oayao_set_heart_motion(mode)` | 设置大心心运动模式(0=跳动,1=呼吸);未知值忽略 |
| `oayao_set_heart_y(fraction)` | 设置大心心垂直位置(画布高度分数 0–1) |
| `oayao_reset_heart_y()` | 恢复大心心默认垂直位置 |
| `oayao_default_heart_y()` | 当前画布下默认垂直位置(高度分数) |

**CalendarManager**(`ios/Oayao/CalendarManager.swift`):

- 按 `SettingsStore.calendarName` 解析规范日历:优先可写 iCloud 日历,其次任意可写日历,再次只读共享日历(仍可提供爱心),均不存在则创建于 iCloud 源
- 同步当天事件:每个非标记事件调用 `oayao_spawn_heart`,随后以全部活跃 ID 调用 `oayao_sync_hearts`
- 监听 `EKEventStoreChanged`,日历内容变化时自动重新解析并同步
- 天数计数器锚定:读取最新的「开始的地方」标记事件,将 notes 中的日期推送到渲染层;标记接近 4 年查询窗口边缘时按当天日期重拷一份
- 提供事件 CRUD、`calshow:` 链接分享与日历可共享性检测

**UI 层**:点击画布爱心 → `EventDetailSheet`(medium/large detent);右下角悬浮按钮 → `AddEventSheet` / `SettingsSheet`(iOS 26+ 使用玻璃效果,旧版本回退为 ultraThinMaterial)。

## Web 架构

- `pnpm dev` 启动 Vite 开发服务器,`zigWatchPlugin`(见 `vite.config.ts`)监听 `.zig` 文件变更,自动执行 `zig build web -Dtarget=wasm32-emscripten` 并将产物拷贝至 `web/public/`
- `web/index.html` 加载 WASM 并暴露 `window.wasmReady` Promise;`web/main.ts` 等待 WASM 就绪后挂载覆盖层
- `web/forcast/` 中的按钮 UI 调用 WASM 导出的 `Module._trigger_meteor_shower(x, y)` 触发流星雨
- CI(`.github/workflows/gh-pages.yml`):push 到 `iOS` 分支或 PR 时,使用 Zig master + pnpm 9 + Node 22 构建 WASM 与前端,写入 CNAME `yaoyao.bbki.ng`,由 `peaceiris/actions-gh-pages` 部署至 GitHub Pages(仅 `iOS` 分支实际部署)

## 环境变量

见 `.env.example`:

| 变量 | 必需 | 说明 |
|---|---|---|
| `APP_STORE_KEY_ID` | 是(TestFlight) | App Store Connect API key ID |
| `APP_STORE_ISSUER_ID` | 是(TestFlight) | App Store Connect API issuer ID |
| `APP_VERSION` | 否 | 营销版本号,默认取 `ios/Info.plist` 中的值 |
| `APP_BUILD_NUMBER` | 否 | 构建号,默认按 git commit 数自增 |
| `DEVELOPER_DIR` | 否 | 指向正式版 Xcode(App Store Connect 拒绝 beta 版 Xcode 构建) |
| `API_PRIVATE_KEYS_DIR` | 否 | `AuthKey_<KEY_ID>.p8` 所在目录,默认 `~/.private_keys` |
| `SIGNING_IDENTITY` | 否 | 签名证书名,默认 `Apple Distribution` |
| `PROVISIONING_PROFILE` | 否 | `.mobileprovision` 文件路径 |
| `PREVIEW_DEVICE` | 否 | `preview-ios.sh` 的目标模拟器名称,默认 `iPhone 17` |

## 技术栈

| 层 | 技术 |
|---|---|
| 语言 | Zig 0.14+ |
| 图形 | sokol(Apple 平台 Metal,Web 平台 WebGL2) |
| 着色器 | GLSL → sokol-shdc 编译为 Metal / GLSL ES |
| iOS 宿主 | Swift + SwiftUI + EventKit,部署目标 iOS 15.0,SDK 26.5 |
| Web 宿主 | Emscripten + WebGL2,Vite 6 + TypeScript |
| Web 工具链 | Node.js 22 + pnpm 9 |
| 部署 | TestFlight(iOS)、GitHub Pages(Web,yaoyao.bbki.ng) |

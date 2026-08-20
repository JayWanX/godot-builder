# GitHub Actions：云端编译 Godot 引擎 / 导出 Godot 项目

本仓库内置两套 GitHub Actions 工作流，可在 GitHub 托管的云服务上：

1. **编译 Godot 引擎源码**（入口 `build.yml`，工作流名 **🔨 Godot Engine Build**）——递归编译指定引擎源码并上传构建产物
2. **导出 Godot 项目**（入口 `export.yml`，工作流名 **📦 Godot Project Export**）——用官方或自编译编辑器 + 模板导出指定项目成品

支持的引擎编译平台：**Linux / Windows / macOS / Android / iOS / visionOS / Web** 七大平台。

---

## 一、编译引擎（🔨 Godot Engine Build）

### 工作流总览

```
build.yml（总调度：手动 / API / 被调用 三种触发）
├── 🔍 resolve              解析输入参数 → ref 解析为 engine-sha → 分发到各平台
├── 🐧 build-linux          → linux_builds.yml
├── 🏁 build-windows        → windows_builds.yml
├── 🍎 build-macos          → macos_builds.yml
├── 🤖 build-android        → android_builds.yml
├── 🍏 build-ios            → ios_builds.yml
├── 🥽 build-visionos       → ios_builds.yml（platform=visionos）
└── 🌐 build-web            → web_builds.yml
```

- **build.yml**：总调度。`resolve` 任务负责输入校验、`ref`→commit SHA 解析（`engine-sha`）、与平台分发，按需调用各平台构建工作流
- **各平台构建工作流**（`linux_builds.yml` 等）：既可被 `build.yml` 调用，也可独立手动触发；`ios_builds.yml` 通过 `platform` 参数复用于 iOS 与 visionOS
- **复合 Actions**（`.github/actions/`）：构建流程共享步骤——依赖安装、缓存恢复/保存、配置注入、编译、依赖探测、产物上传
- **兼容性脚本**（`.github/scripts/ensure_standard_includes.py`）：编译前自动为引擎源码补齐缺失的标准库头文件（见「引擎源码兼容性处理」）

### 快速开始

1. 进入仓库 **Actions** → 选择 **🔨 Godot Engine Build** → **Run workflow**
2. 默认参数即编译 `godotengine/godot` 的 `master` 分支 **release 版本发布模板**（默认 target 与 platform 由 `.github/workflow_build.json` 决定）；可按需修改（见「输入参数」）
3. 运行完成后，在各平台 job 的 **Artifacts** 下载产物

### 触发方式

**① 手动触发（UI）**：仓库 **Actions** → **🔨 Godot Engine Build** → **Run workflow**，按需填参数。

**② API 触发（repository_dispatch）**：发送类型为 `godot-build` 的 `repository_dispatch`；参数经 `client_payload` 传入，可覆盖的字段为 **`source`/`ref`/`target`/`platform`**（与 UI 输入同语义，其余如 `profile`/`gdbuild`/`custom-modules` 需在配置文件 `workflow_build.json` 中预定）：

```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer <GITHUB_TOKEN>" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/<owner>/<repo>/dispatches \
  -d '{
    "event_type": "godot-build",
    "client_payload": {
      "source": "godotengine/godot@master",
      "ref": "4.7-stable",
      "target": "template_release",
      "platform": "linux,windows"
    }
  }'
```

**③ 被调用（workflow_call）**：`export.yml` 等通过 `uses: ./.github/workflows/build.yml` 调用，传 `with` 参数与 `secrets`。

### 输入参数

`build.yml` 手动触发时可填以下参数（逗号分隔可传多值；留空则读 `.github/workflow_build.json` 配置）：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `project` | 当前仓库 | 待导出的**编译配置来源**仓库 `owner/repo@ref`。该项的 `workflow_build.json` 决定引擎来源与默认平台；留空用当前仓库 |
| `source` | `godotengine/godot@master` | 引擎源码仓库 `owner/repo@ref`。留空则读配 `workflow_build.json` 的 `source` |
| `ref` | `master` | 源码分支 / 标签 / commit，覆盖 `source` 中 `@ref` |
| `target` | 读配置 | 构建目标：`editor` / `template_debug` / `template_release`（逗号分隔，取第一个） |
| `platform` | 读配置 | 构建平台，逗号分隔（如 `linux,windows`）；留空读配置数组全部 |

其余编译选项（`profile`、`gdbuild`、`custom-modules` 等）不走 UI，通过 `.github/workflow_build.json` 与待导出项目的 `build/` 配置（见下「编译配置」）。

### 编译配置（workflow_build.json）

`.github/workflow_build.json` 控制构建默认值。示例：

```json
{
  "source": "godotengine/godot@master",
  "target": ["template_release"],
  "platform": ["linux", "windows", "macos", "android", "ios", "visionos"],
  "profile_path": "build/profile.py",
  "gdbuild_path": "build/project.gdbuild",
  "custom_modules": [],
  "upload_artifact": true
}
```

| 字段 | 说明 |
| --- | --- |
| `source` | 引擎来源 `owner/repo@ref` |
| `target` | 构建目标数组 |
| `platform` | 构建平台数组 |
| `profile_path` | SCons profile 文件相对于待导出项目仓库的路径，默认 `build/profile.py` |
| `gdbuild_path` | `.gdbuild` 构建配置相对于待导出项目仓库的路径，默认 `build/project.gdbuild` |
| `custom_modules` | 自定义 C++ 模块仓库列表（`owner/repo[@ref]`） |
| `upload_artifact` | 是否上传构建产物 |

**配置注入方式**：编译用的 `profile.py` 与 `project.gdbuild` 默认从**待导出项目仓库的 `build/`** 读取（以 `repo:<project>@<ref>:build/profile.py` 形式注入）；`profile_path` / `gdbuild_path` 可自定义路径，`godot-config-inject` 支持两种来源，也可在工作流 UI 中覆盖：

| 格式 | 说明 | 示例 |
| --- | --- | --- |
| `repo:<owner/repo>[@<ref>]:<path>` | 浅克隆远程仓库后复制（配合 `GIT_PAT` 可访问私有仓库） | `repo:myorg/myconfigs@main:custom.py` |
| `file:<path>` | 从已检出的引擎仓库中复制指定路径 | `file:custom.py` |

### 所需 Secrets

在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 必需 | 说明 |
| --- | --- | --- |
| `GIT_PAT` | 否 | 访问**私有仓库**的 GitHub Token（PAT 或 GitHub App Token）。用途：① 检出私有引擎仓库；② `repo:` 模式与 `custom-modules` 克隆。以 `git insteadOf` URL 重写注入，子模块同样生效。未设置仅可访问公开仓库。只需对私有仓库 **`Contents: Read`** 只读权限 |
| `SERVICE_ACCOUNT_KEY` | Android 平台 | 下载 Android SDK 组件所需的服务账号密钥 |
| `ENCRYPTION_KEY` | 否 | Godot **PCK 加密密钥**（十六进制）。编译时作为 `SCRIPT_AES256_ENCRYPTION_KEY` 注入；导出时经 `--script-encryption-key` 嵌入二进制。若项目 `encrypt_pck=true` 则必需，留空产出明文 PCK |

### 各平台构建明细

| 平台 | Runner | 构建目标 |
| --- | --- | --- |
| Linux | ubuntu-22.04 | `editor`、`template_release`、`Minimal template`（最小化裁剪模板） |
| Windows | windows-latest | `editor`、`template_release`（MSVC；D3D12 / ANGLE / WinRT / AccessKit 按需自动下载） |
| macOS | macos-26 | `editor`、`template_release`。x86_64 与 arm64 **并行构建**，再由 `merge-macos` 用 `lipo` 合并为 universal |
| Android | ubuntu-24.04 | `editor`（arm64，含 Horizon OS / PICO OS 变体）、`template_debug`（含 Gradle 模板生成） |
| iOS | macos-26 | 按所选 `target` 构建单任务 |
| visionOS | macos-26 | 经 `ios_builds.yml`（`platform=visionos`），按所选 `target` 构建单任务 |
| Web | ubuntu-24.04 | `template_release`（wasm64+threads / wasm32 无线程两种变体，Emscripten 4.0.11） |

**target 支持速查**：`template_debug` 仅 Android 支持（Android 特有调试模板）；macOS/iOS/visionOS 为单任务构建。

构建完成后各平台执行冒烟测试（Linux/Windows/macOS/Web 对产物跑 `godot --version`；Android 检查 APK/AAR 产物存在；iOS/visionOS 产物无法在 runner 运行，仅上传不测试）。

### 产物命名

仓库名的 `/` 会被替换为 `_`（如 `godotengine/godot` → `godotengine_godot`，GitHub 不允许 Artifact 及缓存名含 `/`）。各平台的 Artifact / 缓存以 `<repo-safe>-<平台>-<变体>` 命名：

| 平台 | 产物名（`<repo-safe>` 为其前缀） |
| --- | --- |
| Linux | `-linux-editor` / `-linux-template` / `-linux-template-minimal` |
| Windows | `-windows-editor` / `-windows-template` |
| macOS | 单架构 `-macos-editor-x86_64` / `-macos-template-arm64` 等；`merge-macos` 合并后为 `-macos-editor` / `-macos-template_release`（universal） |
| Android | `-android-editor` / `-android-template-arm64`；editor 另有 `-horizonos` / `-picoos` 变体 |
| iOS / visionOS | `-<ios|visionos>-<target>`（如 `-ios-editor`） |
| Web | `-web-template`（wasm64+threads） / `-web-nothreads-template`（wasm32 无线程） |

### 缓存

各平台以「`<repo-safe>-<平台>-<变体>`」（同上表，即 `cache-name`）作为缓存键的一部分，恢复/保存 SCons 编译缓存（目录默认 `.scons_cache/`）。`engine-sha` 由 `resolve` 将 `ref` 解析为具体 commit（`git ls-remote`），故同一提交完全命中缓存，分支未更新时命中前缀缓存，更新后自动失效重建。缓存恢复失败不影响构建（`continue-on-error`）。

---

## 二、导出项目（📦 Godot Project Export）

`export.yml` 用于把指定 Godot 项目导出为各平台成品。三种导出类型：

- **official**：用官方编辑器 + 官方模板导出（不编译任何东西，需指定 `official-version`）
- **custom_build**：先调用 `build.yml` 编译同源编辑器 + 模板，再导出
- **auto**：检测待导出项目是否有 `workflow_build.json`——有则 `custom_build`，无则 `official`

### 触发方式

仅 **手动触发（UI）**：仓库 **Actions** → **📦 Godot Project Export** → **Run workflow**。

### 输入参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `project` | 当前仓库 | 待导出项目仓库 `owner/repo@ref`（需含 `project.godot`、`export_presets.cfg`）。留空导出当前仓库 |
| `presets` | 读配置 | 要导出的预设名（`export_presets.cfg` 中的 `name`，逗号分隔）。留空读 `.github/workflow_export.json` |
| `export-type` | `default` | `default`（读配置）/ `auto`（自动判断）/ `official` / `custom_build` |
| `official-version` | 空 | official 模式的官方引擎版本（如 `4.7.2-stable`），用于下载官方编辑器与模板。留空读配置 `official_version` |

### 导出配置文件（workflow_export.json）

`.github/workflow_export.json` 控制导出默认值：

```json
{
  "export_presets": ["Windows Desktop", "Linux/X11", "macOS"],
  "export_type": "official",
  "official_version": "4.7.2-stable",
  "upload_artifact": true
}
```

- `export_presets`：默认预设名列表
- `export_type`：默认导出类型
- `official_version`：official 模式默认版本
- `upload_artifact`：是否上传产物

### 流程概览（custom_build 时）

```
export.yml
├── 🔍 resolve                  解析参数、推导平台（从 export_presets.cfg 的 platform 字段）
├── 🔨 build-editor / build-templates    （custom_build）调用 build.yml 编译编辑器与模板
├── 📦 export-desktop           导出 Windows/Linux/macOS/Web
├── 📦 export-android           导出 Android
├── 🔨 build-ios-editor         （custom_build）编译 macOS 编辑器
├── 📦 export-ios / export-visionos      导出 iOS / visionOS
```

### 项目目录要求

被导出的项目需在根目录含：

- `project.godot`：项目配置
- `export_presets.cfg`：导出预设（若 `encrypt_pck=true`，需配置 `ENCRYPTION_KEY` secret，见「所需 Secrets」）
- `build/`（可选，custom_build 时）：引擎编译配置——`profile.py`（SCons 参考配置）、`project.gdbuild`（类型裁剪）

### 注意事项

- 产物上传至 **Actions → 本次运行 → Artifacts**，默认保留 30 天
- 若项目 `export_presets.cfg` 启用 `encrypt_pck=true`，需仓库 Secrets 配置 `ENCRYPTION_KEY`；导出时以 `--script-encryption-key` 注入并嵌入二进制。留空则自动关闭加密、产出明文 PCK
- macOS/iOS/visionOS 消耗 macOS runner 配额；Android 需要 `SERVICE_ACCOUNT_KEY`

---

## 三、引擎源码兼容性处理

所有构建作业在编译前运行 `.github/scripts/ensure_standard_includes.py`（导出链的 custom_build 同样执行）：为依赖标准库传递包含的引擎源码补齐缺失头文件（如 `<memory>` / `<mutex>`），兼容新版编译器与精简配置（如 `threads=no`）。

- 幂等：已自包含的文件零修改；仅插入头文件，不改写既有内容
- 若引擎版本引入脚本未覆盖的新缺失头，编译错误会直接暴露，届时扩展脚本内 `HEADER_FAMILIES` 映射即可

---

## 四、SCons 构建选项

工作流不内置任何 SCons 默认标志。编译时的 SCons 参数通过 `profile.py`（待导出项目 `build/` 下的键值赋值文件，随引擎源码一起注入）控制，例如：

- 构建目标 / 架构：`target = "template_release"`、`arch = "x86_64"`
- 功能裁剪：`disable_3d = "yes"`、`disable_physics_2d = "yes"`
- 优化 / 发布：`optimize = "size_extra"`、`production = "yes"`、`lto = "full"`
- 模块开关：`module_freetype_enabled = "yes"`

用户可直接编辑待导出项目的 `build/profile.py` 配置这些选项。

---

## 五、通用注意事项

- **安全校验**：`resolve` 任务对所有输入做白名单校验（target / 平台 / 仓库格式）；`repo:` 模式拒绝含 `..` 的路径；所有用户输入仅经环境变量传递，避免表达式注入
- **依赖固定**：所有第三方 Actions（checkout、cache、setup-python/java、emsdk、upload/download-artifact 等）均**固定到 commit SHA**（注释标注版本号）；`.github/dependabot.yml` 每周自动为 Actions 创建更新 PR
- **产物保留**：编译产物默认保留 60 天（`upload-artifact` 复合 Action 的 `retention-days` 输入）
- **并发控制**：`build.yml` 按「工作流 + 事件类型 + ref」建立并发组，相同 ref 的重复触发不会同时执行
- **Linux 最小模板**：仅 `linux_builds.yml` 的矩阵含 Minimal 变体，该变体关闭 3D / 物理 / 模块等以最小化体积
- **GitHub 托管环境限制**：macOS / iOS / visionOS 消耗 macOS runner 配额；私有仓库构建需 `GIT_PAT`；Android 需要 `SERVICE_ACCOUNT_KEY`
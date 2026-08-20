# GitHub Actions：云端编译 Godot 引擎

本仓库内置一套完整的 GitHub Actions 工作流，可在 GitHub 托管的云服务器上直接编译 **Godot 引擎源码**（无需本地工具链），产物上传为 Artifact 供下载。支持 Linux / Windows / macOS / Android / iOS / Web 六大平台。

## 工作流总览

```
runner.yml（总调度，可选手动触发或 API 触发）
├── 🔍 resolve          解析输入参数，分发到各平台
├── 🐧 linux-build      → linux_builds.yml
├── 🏁 windows-build    → windows_builds.yml
├── 🍎 macos-build      → macos_builds.yml
├── 🤖 android-build    → android_builds.yml
├── 🍏 ios-build        → ios_builds.yml
└── 🌐 web-build        → web_builds.yml
```

- **runner.yml**：入口工作流，`resolve` 任务负责输入校验、ref→提交 SHA 解析（`engine-sha`）与平台分发，按需调用各平台构建工作流
- **各平台构建工作流**（`linux_builds.yml` 等）：既可被 `runner.yml` 调用，也可独立手动触发
- **复合 Actions**（`.github/actions/`）：构建流程的共享步骤，包括依赖安装、缓存恢复/保存、配置注入、编译与产物上传

## 快速开始

1. 进入仓库 **Actions** → 选择 **🔗 Godot Remote Build** → **Run workflow**
2. 保持默认参数即编译 `godotengine/godot` 的 `master` 分支编辑器（全部六平台）；按需修改（见下「输入参数」与「输入示例」）
3. 等待运行完成后，在各平台 job 的 **Artifacts** 中下载产物

## 触发方式

### 1. 手动触发（UI）

仓库页面 **Actions** → 选择 **🔗 Godot Remote Build** → **Run workflow**，按需填写参数。

### 2. API 触发（repository_dispatch）

发送类型为 `godot-build` 的 `repository_dispatch` 事件，参数通过 `client_payload` 传递（字段名使用下划线命名）：

```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer <GITHUB_TOKEN>" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/<owner>/<repo>/dispatches \
  -d '{
    "event_type": "godot-build",
    "client_payload": {
      "repository": "godotengine/godot",
      "ref": "4.7-stable",
      "target": "template_release",
      "platform": "all",
      "scons_flags": "debug_symbols=no",
      "profile": "repo:myorg/myconfigs@main:custom.py",
      "encryption_key": "abc123...",
      "upload_artifact": true
    }
  }'
```

## 输入参数

以下参数在 `runner.yml` 与各平台工作流中一致：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `repository` | `godotengine/godot` | 引擎源码仓库（`owner/repo`），支持私有仓库（需 `GIT_PAT`） |
| `ref` | `master` | 源码分支、标签或提交 SHA |
| `target` | `editor` | 构建目标：`editor` / `template_debug` / `template_release`（各平台支持的矩阵见「构建矩阵与 target 过滤」） |
| `platform` | `all` | 构建平台（仅 `runner.yml`），**支持逗号分隔多选**：`linux,windows`；`all` 表示全部六平台 |
| `scons-flags` | 空 | 附加 SCons 标志，追加到矩阵标志之后 |
| `profile` | 空 | `custom.py` 来源（见下文「配置来源与填写示例」），为空则不注入 |
| `gdbuild` | 空 | `.gdbuild` 构建配置文件来源（见下文），为空则不注入 |
| `custom-modules` | 空 | 自定义模块仓库列表（见下文） |
| `encryption-key` | 空 | Godot 脚本加密密钥（**十六进制字符串**），作为 `SCRIPT_AES256_ENCRYPTION_KEY` 注入构建环境 |
| `upload-artifact` | `true` | 是否上传构建产物 |

### 配置来源与填写示例（`profile` / `gdbuild` / `custom-modules`）

`profile` 与 `gdbuild` 支持相同的三种来源，`custom-modules` 为仓库列表；这三项是 workflow_dispatch 表单中需要特定格式的输入（其余输入为普通值，如 `repository=godotengine/godot`、`ref=4.7-stable`、`target=template_release`、`platform=windows,linux`、`scons-flags=production=yes`）：

| 输入 | 格式 | 说明 | 示例填写值 |
| --- | --- | --- | --- |
| `profile` | `inline:<base64>` | 内容以 Base64 编码内联传入，自动解码写入 `custom.py` | `inline:IyBjdXN0b20gc2V0dGluZ3M=`（即 `# custom settings` 的 base64） |
| | `file:<path>` | 从已检出的引擎仓库中复制指定路径文件 | `file:custom.py` |
| | `repo:<owner/repo>[@<ref>]:<path>` | 浅克隆任意远程仓库后复制指定路径文件（可配合私有仓库使用，见下文 `GIT_PAT`） | `repo:myorg/myconfigs@main:custom.py` |
| `gdbuild` | 同 `profile` | 同上，写入 `project.gdbuild` | `repo:myorg/myconfigs@main:project.gdbuild` |
| `custom-modules` | `owner/repo[@ref]`，逗号分隔 | 附加的自定义 C++ 模块仓库（`@ref` 可省略，默认分支） | `myorg/mymodule@dev,myorg/another` |

## 所需 Secrets

| Secret | 必需 | 说明 |
| --- | --- | --- |
| `GIT_PAT` | 否 | 访问**私有仓库**的 GitHub Token（PAT 或 GitHub App Token）。用于：① 检出私有**引擎仓库**（checkout 步骤，`GIT_PAT` 或 `github.token` 兜底）；② `repo:` 模式与 `custom-modules` 克隆。以 `git insteadOf` URL 重写方式注入，子模块克隆同样生效。未设置时仅可访问公开仓库。**只需对这些私有仓库的只读权限（Fine-grained PAT 勾 `Contents: Read` 即可），无需写权限** |
| `SERVICE_ACCOUNT_KEY` | 是（Android 平台） | 下载 Android SDK 组件所需的服务账号密钥 |

在仓库 **Settings → Secrets and variables → Actions** 中配置。

## 各平台构建明细

| 平台 | Runner | 构建产物 |
| --- | --- | --- |
| Linux | ubuntu-22.04（为兼容旧系统保留 LTS 版本） | Editor、Template、Minimal template（全功能裁剪） |
| Windows | windows-latest | Editor、Template（MSVC，D3D12 / ANGLE / WinRT / AccessKit 自动下载） |
| macOS | macos-26 | Editor、Template。x86_64 与 arm64 **并行构建**，再由 `merge-macos` 任务用 `lipo` 合并为 universal 单一产物 |
| Android | ubuntu-24.04 | Editor（arm64，含 Horizon OS / PICO OS 变体）、Template arm64（含 Gradle 模板生成） |
| iOS | macos-26 | 按所选 target 构建单任务 |
| Web | ubuntu-24.04 | Template（wasm64+threads / wasm32 无线程两种变体，Emscripten 4.0.11） |

各平台构建完成后自动执行产物冒烟测试（`godot --version`，Android 为检查 APK / AAR 产物存在；iOS 产物无法在 runner 上运行，仅上传不测试）；构建选项完全由 `profile` 与 `scons-flags` 输入控制。

### 产物命名

Artifact 名称格式：`<repo-safe>-<cache-name>`。**GitHub 不允许 Artifact 名称包含 `/`**，因此仓库名中的 `/` 会替换为 `_`（如 `godotengine/godot` → `godotengine_godot`）：`godotengine_godot-windows-editor`。macOS 合并产物为 `godotengine_godot-macos-editor`（universal）。

### 构建矩阵与 target 过滤

各平台矩阵行按构建目标划分（如 Linux：Editor / Template / Minimal template），仅当 `matrix.target == inputs.target` 时才运行，避免重复构建与冒烟测试误判。用户选择的 target 与矩阵行一一对应：`editor` 只构建编辑器行，`template_release` 只构建模板行，`template_debug` 仅 Android 支持。

## 缓存

各平台按 `<repo-safe>-<矩阵名>|<engine-sha>|<commit>` 为键恢复/保存 SCons 编译缓存（`cache_path`），二次构建可大幅提速。其中 `engine-sha` 由 `runner.yml` 将 `ref` 解析为具体提交 SHA（`git ls-remote`），因此**分支 / 标签 / 提交三者会共享或细分缓存**：同一提交走完全命中，分支内未更新时命中该提交前缀缓存，更新后自动失效重建。缓存恢复失败不影响构建（`continue-on-error`）。

## SCons 构建选项

工作流不内置任何 SCons 默认标志，所有构建选项由 `profile`（custom.py）与 `scons-flags` 输入控制。常用配置：

- 开发构建（警告即错误、单元测试、严格检查）：`dev_mode=yes`
- 发布优化（LTO、静态链接、去除调试符号）：`production=yes`

两者可通过 `profile` 输入或 GUI 生成的 profile.py 设置。

## 自导出工作流（🔨 Build & Export GodotBuilder）

除远程编译 Godot 引擎外，本仓库还内置一个自用工作流：**按 `build/` 目录下的配置构建 Godot 导出模板，导出本项目（GodotBuilder 工具）本身**，产物上传为 Artifact。入口：**Actions → 🔨 Build & Export GodotBuilder → Run workflow**。

流程概览：

```
🔨 Build & Export GodotBuilder（workflow_dispatch）
├── 🐧 build-templates-linux    检出引擎 → 注入 build/ 配置 → 编译 Linux 模板 + Windows 模板（MinGW 交叉编译）
├── 🍎 build-template-macos     检出引擎 → 注入 build/ 配置 → 编译 macOS 模板（universal）
└── 📦 export                   下载同名编辑器 + 模板 → 按 build/export_presets.cfg 导出 → 上传产物
```

### 输入参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `engine-ref` | `4.7.2-stable` | Godot 引擎发布标签，用于检出模板源码并下载同名编辑器（编辑器与模板版本必须一致） |
| `target` | `template_release` | 模板目标：`template_release` / `template_debug` |
| `presets` | `Windows Desktop,Linux/X11,macOS` | 要导出的预设名称（`build/export_presets.cfg` 中的 `name`，逗号分隔） |
| `encryption-key` | 空 | 脚本加密密钥（十六进制，至少 16 位）；留空则关闭 PCK 加密 |
| `upload-artifact` | `true` | 是否上传导出产物 |

### build/ 目录

- `build/profile.py` + `build/project.gdbuild`：模板构建配置。工作流将其注入引擎源码根目录（`custom.py` / `project.gdbuild`）后执行 `scons` 编译；`profile.py` 中的 `build_profile` 路径会被改写为 `project.gdbuild`
- `build/export_presets.cfg`：导出预设（提交版本），模板路径使用 `@TEMPLATES_DIR@` 占位符，工作流运行时替换为模板下载目录；`export_presets.cfg`（项目根目录的本地版本）仍被 .gitignore 忽略，仅用于本地导出
- `python/`：内嵌 Python 运行时（约 83 MB，`python/embeddings/` + `python/site-packages/`），已纳入版本控制并随导出打包；导出时由 `addons/godot_builder_export/` 插件按目标平台裁剪（仅保留对应平台 embedding）

### 注意事项

- 产物上传至 **Actions → 本次运行 → Artifacts**，默认保留 30 天；模板 Artifact 保留 7 天
- 选择 `encryption-key` 时，导出会以 `--script-encryption-key` 将密钥嵌入二进制以解密自身 PCK；留空时 `encrypt_pck` / `encrypt_directory` 自动关闭
- macOS 模板在 macos 主机上构建（universal），Linux / Windows 模板在同一台 ubuntu 主机上构建，模板 Artifact 由导出任务合并使用
- 本工作流不依赖 `runner.yml`，可独立手动触发

## 注意事项

- **安全校验**：`runner.yml` 的 resolve 任务对所有输入做白名单校验（target / 平台 / 仓库格式），`repo:` 模式拒绝包含 `..` 的路径，`base64 -d` 失败或内容为空时报错退出；所有用户输入仅经环境变量传递，避免表达式注入
- **依赖固定**：所有第三方 Actions（checkout、cache、setup-python/java、emsdk、upload/download-artifact 等）均**固定到 commit SHA**（注释标注版本号），杜绝供应链篡改；`.github/dependabot.yml` 每周自动为 Actions 创建更新 PR
- **产物保留**：上传的 Artifact 默认保留 60 天（`upload-artifact` 复合 Action 的 `retention-days` 输入，可调整）
- **并发控制**：`runner.yml` 按「工作流 + 事件类型 + ref」建立并发组，相同 ref 的重复触发不会同时执行
- **Linux 最小模板**：仅 `linux_builds.yml` 的矩阵包含 Minimal 变体，该变体关闭 3D / 物理 / 模块等以最小化体积
- **GitHub 托管环境限制**：macOS / iOS 构建消耗 macOS runner 配额；私有仓库构建需 `GIT_PAT`；Android 需要 `SERVICE_ACCOUNT_KEY`

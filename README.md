# GodotBuilder

用 Godot 编写的 **Godot 引擎源码图形化编译工具**。解析 `scons --help` 自动生成分组式构建选项界面（含中文汉化），一键调用 SCons 完成引擎编译，无需手动编辑 `custom.py`。

## 功能特性

- **图形化构建选项**
  - 解析源码 `scons --help` 输出，动态生成全部编译选项（bool / 枚举 / 整数 / 字符串 / 路径类型），无需硬编码选项列表
  - 选项按「基础构建目标 / 优化与性能 / 功能开关 / 渲染与图形驱动 / 构建加速与产物 / 性能分析器 / 编译器与工具链 / Windows 平台特定 / 模块 / 内置库」等分组展示，支持分组导航、搜索过滤与逐组重置
  - 中文汉化：`build_options_zh.json` 提供选项名、描述与分组的中文翻译（`version` 字段标注适用的引擎版本）
- **差异式配置模型**
  - 仅将偏离默认值的选项写入 `custom.py`，保持配置文件最小化
  - `modules_enabled_by_default` 总开关自动派生模块选项默认值；依赖规则自动补全强制项（如 ANGLE 未禁用时强制保留 `module_astcenc_enabled`，避免链接失败）
  - 首次解析自动识别源码 `custom.py`，导入后即保留原工程配置
- **配置管理**
  - 一键构建、取消构建（先发送中断让 SCons 优雅退出，超时后强制终止）
  - `custom.py` 导入 / 导出、配置预览窗口
  - 构建日志实时捕获并落盘到可执行文件旁的 `logs/` 目录
- **免安装环境**
  - 内置嵌入式 Python 3.14 运行时（Windows / Linux / macOS 三平台）与 SCons 4.11，首次运行自动解压到可执行文件旁，无需手动安装依赖
  - 设置中可自定义 Python 解释器路径与 SCons 库目录，校验失败自动回退内置
- **源码目录管理**
  - 自动扫描可执行文件旁 `sources/` 目录下的一级子目录，识别 Godot 版本并快速切换
  - 构建前自动检测当前环境可构建的平台列表（`scons platform=list`）
  - 一键在源码目录或程序目录打开系统终端
- **工程集成**
  - `scons --help` 磁盘缓存：缓存键含源码内容哈希，第三方改动 `SConstruct` / `version.py` 后自动失效，可在「更多」菜单手动清除
  - PCK 加密编译密钥注入：设置中配置的密钥以 `SCRIPT_AES256_ENCRYPTION_KEY` 环境变量注入 SCons 子进程，`secrets.dat` 做混淆存储（绑定本机与可执行文件路径）
  - 配套 GitHub Actions 工作流：云端远程编译 Godot 引擎（Linux / Windows / macOS / Android / iOS / Web），并可一键构建导出模板、产出本工具三平台成品，使用说明见 [`.github/README.md`](.github/README.md)

## 获取构建版本

- **预构建版**：从本仓库 **Releases** 页面下载（若已发布）
- **自行构建**：使用 Godot 4.7.x 打开项目，按下方「导出打包」章节导出

## 环境要求

| 环境         | 说明                                                                                      |
| ------------ | ----------------------------------------------------------------------------------------- |
| Godot 编辑器 | 4.7.x（项目使用 Forward Plus 渲染器与 GDScript 4 语法）                                   |
| 目标引擎源码 | 任意版本 Godot 引擎源码（依赖 `SConstruct` 与 `version.py` 完整性校验）                   |
| 编译工具链   | 与官方编译文档一致（如 Windows 需 VS Build Tools，Linux 需 gcc 等）——工具本身不内置编译器 |

编译目标引擎时所需工具链请参考 [Godot 官方编译文档](https://docs.godotengine.org/en/stable/contributing/development/compiling/)。

## 开发运行

1. 使用 Godot 4.7.x 编辑器打开本项目
2. 直接运行主场景 `res://main.tscn`
3. 将 Godot 引擎源码放入可执行文件（编辑器运行模式下为项目目录）旁的 `sources/` 文件夹，或点击源码按钮手动选择

> 开发模式下直接使用项目内的 `python/` 资源目录；导出打包后首次运行会从 PCK 中解压运行时到可执行文件旁。

## 导出打包

- 导出预设见 `build/export_presets.cfg`（提交版本，Windows Desktop / Linux/X11 / macOS 三平台，启用 PCK 加密与脚本加密密钥注入，模板路径用 `@TEMPLATES_DIR@` 占位）；项目根目录的 `export_presets.cfg` 为本地个人预设（含本机模板路径，已被 .gitignore 忽略，仅供本地导出使用）
- 项目自带导出裁剪插件 `addons/godot_builder_export/`（裁剪导出时嵌入的引擎类，减小体积）
- 用于编译本工具自身精简版引擎的配置集中在 `build/` 目录：`profile.py`（SCons 参考配置）、`project.gdbuild`（类型裁剪）、`export_presets.cfg`（导出预设）
- 可在 GitHub Actions 云端一键构建模板并导出三平台成品（自导出工作流），使用说明见 [`.github/README.md`](.github/README.md)

## 目录结构

```
.
├── main.gd / main.tscn      # 主场景与逻辑
├── src/                     # 核心逻辑
│   ├── godot_builder.gd     # 构建器：运行时解压、SCons 调用、环境探测、help 缓存
│   ├── scons_help_parser.gd # scons --help 输出解析
│   ├── build_options.gd     # 选项元数据仓库与分组（含中文汉化合并）
│   ├── config_store.gd      # 配置差异字典 + 依赖规则 + 模块开关派生
│   ├── profile_converter.gd # custom.py <-> 配置字典双向转换
│   ├── secret_store.gd      # PCK 加密密钥混淆存取
│   ├── build_logger.gd      # 构建日志落盘
│   ├── console.gd           # 控制台输出
│   ├── app_data.gd          # 应用数据（exe 旁 app_data.tres）
│   └── utils.gd             # 版本解析、源码扫描、打开终端等工具
├── ui/                      # 界面：panels（表单/分组导航/摘要/控制台）、
│                            #   windows（配置预览）、dialogs（设置）、controls（字段控件/状态栏）
├── addons/
│   ├── pipe_process_runner/ # 进程管道运行器（stdout/stderr 捕获、中断/终止）
│   └── godot_builder_export/ # 导出裁剪插件
├── python/                  # 嵌入式运行时（embeddings/<平台> + site-packages/SCons）
├── assets/                  # 资源目录（UI 图标等）
├── icon.svg / project.godot # 应用图标与 Godot 项目设置
├── build/                   # 本工具自身的构建与导出配置
│   ├── profile.py           # 编译本工具自身的 custom.py 参考配置
│   ├── project.gdbuild      # 精简构建配置（类型裁剪）
│   └── export_presets.cfg   # 导出预设（@TEMPLATES_DIR@ 占位，供 CI 使用）
├── build_options_zh.json    # 构建选项中文汉化数据
└── .github/workflows/       # CI 工作流：云端远程编译引擎 + 自导出本工具三平台成品
```

## 使用流程

1. **选择源码**：点击左上角源码按钮，从 `sources/` 扫描结果或文件对话框中选取 Godot 引擎源码目录
2. **配置选项**：在左侧分组导航与右侧表单中调整编译选项，修改项实时汇总到顶部摘要；支持搜索定位与整组重置
3. **导入/导出**：可将现有 `custom.py` 导入作为配置基础，或将当前配置导出为 `custom.py`
4. **开始构建**：点击「构建」按钮，控制台实时显示 SCons 输出；构建产物位于源码目录 `bin/`，日志保存至程序目录 `logs/`
5. **设置**：在「更多」菜单中配置自定义 Python / SCons 路径、PCK 加密编译密钥、清除 help 缓存或打开终端

## 许可证

[MIT](LICENSE)

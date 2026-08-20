#!/usr/bin/env python3
"""Godot 导出参数解析脚本（由 godot-resolve-export action 调用）

【这个脚本做什么？】
从三个地方收集信息：
  1. workflow_export.json  —— 导出配置文件（预设列表、导出类型、官方版本等）
  2. workflow_build.json   —— 构建配置文件（引擎来源 source 等）
  3. export_presets.cfg    —— 项目预设文件（每个预设对应什么平台）
再加上用户在 GitHub 网页上填的输入（UI 输入），
最终算出"导出需要的一切参数"，写到 $GITHUB_OUTPUT 文件里，
供工作流里的下游任务（build-editor / build-templates / export-*）使用。

【为什么用环境变量传输入？】
GitHub Actions 里用户输入是通过 inputs 传的。为了安全（防止注入攻击），
workflow 把 inputs 先放进环境变量，脚本再从环境变量读，避免把不可信内容
直接拼进代码/命令。
"""
import json      # 用于读写 JSON 配置文件
import os        # 用于读取环境变量
import re        # 用于正则匹配（解析 export_presets.cfg 的 name= / platform= 字段）
import subprocess  # 用于执行 git 命令（克隆远程项目）
import sys       # 用于输出错误信息到 stderr
from pathlib import Path  # 用于跨平台路径操作


# ============================================================
# 工具函数区
# ============================================================

def fail(message: str) -> None:
    """打印 GitHub Actions 的错误标记并终止脚本。

    ::error:: 是 GitHub Actions 的特殊输出格式，
    会让工作流这一步显示为失败并红色高亮。
    """
    print(f"::error::{message}", file=sys.stderr)  # 输出到标准错误流
    sys.exit(1)  # 以退出码 1 结束脚本（表示失败）


def warn(message: str) -> None:
    """打印 GitHub Actions 的警告标记（不会失败，只是提示）。"""
    print(f"::warning::{message}", file=sys.stderr)


def read_json(file_path: str, description: str) -> dict:
    """读取一个 JSON 配置文件并解析为字典。

    [param] file_path   JSON 文件路径
    [param] description 文件的用途描述（用于报错信息，方便人看懂）
    [return] 解析后的字典；文件不存在或格式错误则直接报错退出
    """
    path = Path(file_path)
    # 文件不存在则报错（明确告诉缺的是哪个文件）
    if not path.is_file():
        fail(f"缺少 {description}: {file_path}")
    try:
        # 以 UTF-8 编码打开并解析 JSON
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        # JSON 格式坏了则报错
        fail(f"{description} 解析失败 {file_path}: {e}")


def parse_repo_ref(spec: str, default_ref: str = "master") -> tuple[str, str]:
    """把一个 '所有者/仓库@分支' 字符串拆成（仓库, 分支）两部分。

    [param] spec        形如 "myorg/myproj@main" 的仓库引用
    [param] default_ref 没有写 @分支时使用的默认分支
    [return] (仓库名, 分支名) 二元组
    """
    # @ 前面的部分是仓库（按第一个 @ 分割）
    repo = spec.split("@", 1)[0]
    # 有 @ 就取 @ 后面的分支，没有就用默认分支
    ref = spec.split("@", 1)[1] if "@" in spec else ""
    return repo, ref or default_ref


def clone_project(repo: str, ref: str, dest_dir: str) -> None:
    """浅克隆一个远程 GitHub 仓库到本地临时目录。

    用于"待导出项目是远程仓库"时，把它的配置文件拉下来读取。

    [param] repo     仓库名（owner/repo）
    [param] ref      分支/tag/commit
    [param] dest_dir 克隆到哪个目录
    """
    url = f"https://github.com/{repo}"
    # --depth=1: 只克隆最新一次提交（快）  --quiet: 不打印进度
    subprocess.run(
        ["git", "clone", "--depth=1", "--quiet", "-b", ref, url, dest_dir],
        check=True,        # 克隆失败则抛异常
        capture_output=True,
    )


def derive_platforms(preset_cfg_path: str, selected_presets: list[str]) -> list[str]:
    """从 export_presets.cfg 推导出"被选中的预设"对应的平台列表。

    原理：export_presets.cfg 里每个预设块都有两行关键信息：
        name="Windows Desktop"      ← 预设的名字
        platform="Windows Desktop"  ← 这个预设属于哪个平台
    脚本遍历文件，找出"名字在 selected_presets 里"的预设，
    把它的 platform 映射成平台短名（如 windows / linux / macos）。

    [param] preset_cfg_path   export_presets.cfg 文件路径
    [param] selected_presets  用户选中的预设名列表
    [return] 去重排序后的平台短名列表（如 ["macos", "windows"]）
    """
    # 平台长名 → 平台短名 的映射表（Godot 预设平台名 → 我们的平台代号）
    platform_mapping = {
        "Windows": "windows",
        "Linux": "linux",
        "macOS": "macos",
        "Android": "android",
        "iOS": "ios",
        "VisionOS": "visionos",
        "Web": "web",
    }
    platforms: set[str] = set()  # 用集合自动去重
    current_preset_name = None   # 记录当前遍历到哪个预设的名字

    with open(preset_cfg_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()  # 去掉首尾空白
            # 匹配 name="xxx" 行，记住当前预设名
            name_match = re.match(r'name="([^"]*)"', line)
            # 匹配 platform="xxx" 行，取得平台长名
            platform_match = re.match(r'platform="([^"]*)"', line)

            if name_match:
                current_preset_name = name_match.group(1)  # 记住预设名
            elif platform_match:
                platform_long_name = platform_match.group(1)  # 该预设的平台长名
                # 仅当这个预设是用户选中的，才收集它的平台
                if current_preset_name in selected_presets:
                    for long_name, short_name in platform_mapping.items():
                        if platform_long_name.startswith(long_name):
                            platforms.add(short_name)
                            break
                    else:
                        # for...else：循环没 break（没匹配上）才执行
                        warn(f"预设 '{current_preset_name}' 平台 '{platform_long_name}' 无法识别")
                current_preset_name = None  # 处理完当前预设，重置
    return sorted(platforms)  # 返回排序后的平台列表（保证顺序稳定）


# ============================================================
# 主函数
# ============================================================

def main() -> None:
    # ---- 1. 读取 UI 输入（用户在工作流页面上填的值）----
    ui_project = os.environ.get("UI_PROJECT", "")      # 待导出项目（owner/repo@ref）
    ui_presets = os.environ.get("UI_PRESETS", "")      # 要导出的预设（逗号分隔）
    ui_type = os.environ.get("UI_TYPE", "")            # 导出类型
    ui_version = os.environ.get("UI_VERSION", "")      # official 模式的官方版本

    # ---- 2. 读取配置文件路径（workflow 检出后通过环境变量提供）----
    export_cfg_path = os.environ.get("EXPORT_CONFIG", ".github/workflow_export.json")
    build_cfg_path = os.environ.get("BUILD_CONFIG", ".github/workflow_build.json")
    preset_cfg_path = os.environ.get("PRESET_CFG", "export_presets.cfg")
    current_repo = os.environ.get("CURRENT_REPO", "")  # 当前所在仓库
    current_sha = os.environ.get("CURRENT_SHA", "")    # 当前 commit

    # 读取两个 JSON 配置文件（不存在则报错）
    export_cfg = read_json(export_cfg_path, "workflow_export.json")
    build_cfg = read_json(build_cfg_path, "workflow_build.json")

    # ---- 3. 确定待导出项目 ----
    # 用户填了 project 就用它；没填就用当前仓库
    if ui_project:
        project_repo, project_ref = parse_repo_ref(ui_project)
    else:
        project_repo, project_ref = current_repo, current_sha

    # ---- 4. 确定导出类型 ----
    export_type = ui_type
    # 值为空或 default 时，读配置文件里的 export_type（默认 auto）
    if export_type in ("", "default"):
        export_type = export_cfg.get("export_type", "auto")
    # auto 模式：看有没有 workflow_build.json
    #   有 → 说明是自定义引擎项目 → custom_build（自编译）
    #   无 → 说明是官方引擎项目 → official（用官方）
    if export_type == "auto":
        export_type = "custom_build" if Path(build_cfg_path).is_file() else "official"
        print(f"export-type=auto → {export_type}")
    # 校验最终值合法
    if export_type not in ("official", "custom_build"):
        fail(f"unsupported export-type '{export_type}'")

    # ---- 5. 确定引擎来源与版本 ----
    if export_type == "official":
        # official：引擎固定官方 godotengine/godot，版本用 UI 或配置的 official_version
        version = ui_version or export_cfg.get("official_version", "")
        if not version:
            fail("official 模式需提供 official-version（UI 或 workflow_export.json）")
        engine_repo, engine_ref = "godotengine/godot", version
    else:
        # custom_build：引擎来源从 workflow_build.json 的 source 字段读取
        source = build_cfg.get("source", "godotengine/godot@master")
        engine_repo, engine_ref = parse_repo_ref(source)

    # 仓库名安全形式：把 '/' 换成 '_'（因为 artifact 命名不允许有 '/'）
    repo_safe = engine_repo.replace("/", "_")

    # ---- 6. 确定预设列表 ----
    if ui_presets:
        presets = ui_presets
    else:
        # 从配置文件读全部预设，用逗号连接
        presets = ",".join(export_cfg.get("export_presets", []))
        if not presets:
            fail("未解析到任何导出预设")
    # 把逗号分隔的预设字符串拆成列表（去掉空项）
    selected_preset_list = [p.strip() for p in presets.split(",") if p.strip()]

    # ---- 7. 从预设推导平台 ----
    preset_cfg = Path(preset_cfg_path)
    # 如果本地没有 export_presets.cfg 且待导出项目是远程仓库，则克隆获取
    if not preset_cfg.is_file() and project_repo != current_repo:
        temp_dir = os.environ.get("RUNNER_TEMP", "/tmp")
        clone_project(project_repo, project_ref, os.path.join(temp_dir, "proj_preset"))
        preset_cfg = Path(temp_dir) / "proj_preset" / "export_presets.cfg"

    # 有预设文件则推导平台，否则回退默认桌面三平台
    if preset_cfg.is_file():
        platforms = derive_platforms(str(preset_cfg), selected_preset_list)
        if not platforms:
            fail("所选预设未推导到任何平台")
    else:
        warn("未找到项目 export_presets.cfg，平台推导失败，回退 linux windows macos")
        platforms = ["linux", "windows", "macos"]

    # ---- 8. 输出所有参数到 $GITHUB_OUTPUT ----
    # $GITHUB_OUTPUT 文件是 GitHub Actions 约定的输出通道：
    # 往里面写 "key=value"，下游任务就能用 steps.<id>.outputs.key 读取
    output_path = os.environ.get("GITHUB_OUTPUT", "")
    output_lines = [
        ("presets", presets),                                  # 预设列表
        ("export-type", export_type),                          # 导出类型
        ("upload-artifact", str(export_cfg.get("upload_artifact", True)).lower()),  # 是否上传
        ("editor-platform", "linux"),                          # 导出编辑器平台（桌面用 linux）
        ("need-ios", str("ios" in platforms).lower()),         # 是否需要 iOS
        ("need-visionos", str("visionos" in platforms).lower()), # 是否需要 visionOS
        ("need-android", str("android" in platforms).lower()), # 是否需要 Android
        ("template-platforms", ",".join(platforms)),           # 需要模板的平台
        ("engine-source", f"{engine_repo}@{engine_ref}"),      # 引擎来源
        ("engine-ref", engine_ref),                            # 引擎引用
        ("repo-safe", repo_safe),                              # 仓库安全名
        ("project-repo", project_repo),                        # 待导出项目仓库
        ("project-ref", project_ref),                          # 待导出项目引用
    ]
    # 写进 GITHUB_OUTPUT 文件（追加模式）
    if output_path:
        with open(output_path, "a", encoding="utf-8") as f:
            for key, value in output_lines:
                f.write(f"{key}={value}\n")
    # 同时在日志里打印，方便人查看
    for key, value in output_lines:
        print(f"{key}={value}")
    print(f"presets={presets} type={export_type} platforms={' '.join(platforms)}")


# ============================================================
# 程序入口：只有直接运行本脚本时才执行 main()
# （被别的模块 import 时不会执行，避免副作用）
# ============================================================
if __name__ == "__main__":
    main()

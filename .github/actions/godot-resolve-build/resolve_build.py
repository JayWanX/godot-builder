#!/usr/bin/env python3
"""Godot 引擎构建参数解析脚本（由 godot-resolve-build action 调用）

【这个脚本做什么？】
从 workflow_build.json 配置文件和用户的 UI 输入中，
解析出"编译引擎"所需的全部参数（引擎仓库、引用、目标、平台、编译配置等），
写到 $GITHUB_OUTPUT 文件里，供 build.yml 的 6 个平台构建任务使用。

【和 resolve.py（导出解析）的区别？】
  resolve.py        —— 面向"导出"，解析预设、平台、导出类型
  本脚本 resolve_build.py —— 面向"编译"，解析引擎来源、构建目标、平台矩阵
"""
import json         # 用于读写 JSON 配置文件
import os           # 用于读取环境变量
import re           # 用于正则匹配（判断 40 位 SHA）
import subprocess   # 用于执行 git 命令（克隆远程项目、查 SHA）
import sys          # 用于输出错误信息到 stderr
from pathlib import Path  # 用于跨平台路径操作


# ============================================================
# 工具函数区
# ============================================================

def fail(message: str) -> None:
    """打印 GitHub Actions 的错误标记并终止脚本。

    ::error:: 会让工作流这一步显示为失败。
    """
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def warn(message: str) -> None:
    """打印 GitHub Actions 的警告标记（不会失败，只是提示）。"""
    print(f"::warning::{message}", file=sys.stderr)


def read_json(file_path: str, description: str) -> dict:
    """读取一个 JSON 配置文件并解析为字典。

    [param] file_path   JSON 文件路径
    [param] description 文件用途描述（用于报错信息）
    [return] 解析后的字典；文件缺失或格式错误则报错退出
    """
    path = Path(file_path)
    if not path.is_file():
        fail(f"缺少 {description}: {file_path}")
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        fail(f"{description} 解析失败 {file_path}: {e}")


def parse_repo_ref(spec: str, default_ref: str = "master") -> tuple[str, str]:
    """把一个 '所有者/仓库@分支' 字符串拆成（仓库, 分支）两部分。

    [param] spec        形如 "myorg/myproj@main" 的仓库引用
    [param] default_ref 没有写 @分支时使用的默认分支
    [return] (仓库名, 分支名) 二元组
    """
    repo = spec.split("@", 1)[0]
    ref = spec.split("@", 1)[1] if "@" in spec else ""
    return repo, ref or default_ref


def clone_project(repo: str, ref: str, dest_dir: str) -> None:
    """浅克隆一个远程 GitHub 仓库到本地临时目录。

    用于"待导出项目是远程仓库"时，把它拉下来读取 workflow_build.json。

    [param] repo     仓库名（owner/repo）
    [param] ref      分支/tag/commit
    [param] dest_dir 克隆到哪个目录
    """
    url = f"https://github.com/{repo}"
    subprocess.run(
        ["git", "clone", "--depth=1", "--quiet", "-b", ref, url, dest_dir],
        check=True,        # 克隆失败则抛异常
        capture_output=True,
    )


def resolve_engine_sha(repo: str, ref: str) -> str:
    """把引擎的分支名/tag 解析成具体的 commit SHA。

    为什么需要 SHA？因为编译缓存（cache）用 SHA 当 key。
    同一个分支可能随时有新提交，用分支名当缓存 key 会导致缓存不稳定，
    而 SHA 是固定的，能保证缓存精准命中。

    [param] repo 引擎仓库（owner/repo）
    [param] ref  分支/tag/commit
    [return] 40 位 commit SHA；解析失败则返回 "unknown"
    """
    # git ls-remote 查询远程仓库里 ref 对应的 SHA
    proc = subprocess.run(
        ["git", "ls-remote", f"https://github.com/{repo}.git",
         f"{ref}^{{}}",           # tag 对象指向的 commit
         f"refs/heads/{ref}",     # 分支 ref
         f"refs/tags/{ref}^{{}}", # tag 指向的 commit
         ],
        capture_output=True, text=True,
    )
    for line in proc.stdout.splitlines():
        parts = line.split()
        if parts:
            return parts[0]  # 第一列就是 SHA
    # 如果用户传的本身就是 40 位十六进制 SHA，直接用它
    if re.fullmatch(r"[0-9a-f]{40}", ref):
        return ref
    warn(f"could not resolve engine ref '{ref}' to a commit SHA.")
    return "unknown"


# ============================================================
# 主函数
# ============================================================

def main() -> None:
    # ---- 1. 读取 UI 输入（用户在工作流页面上填的值）----
    ui_project = os.environ.get("UI_PROJECT", "")      # 待导出项目（编译配置来源）
    ui_source = os.environ.get("UI_SOURCE", "")        # 引擎来源
    ui_ref = os.environ.get("UI_REF", "")              # 引擎引用
    ui_target = os.environ.get("UI_TARGET", "")        # 构建目标
    ui_platform = os.environ.get("UI_PLATFORM", "")    # 平台
    ui_profile = os.environ.get("UI_PROFILE", "")      # SCons 配置
    ui_gdbuild = os.environ.get("UI_GDBUILD", "")      # .gdbuild 配置
    payload = os.environ.get("PAYLOAD", "")            # API 触发时的载荷
    event_name = os.environ.get("EVENT_NAME", "")      # 触发方式名
    current_repo = os.environ.get("CURRENT_REPO", "")  # 当前仓库
    current_sha = os.environ.get("CURRENT_SHA", "")    # 当前 commit

    # ---- 2. repository_dispatch（API 触发）时，从 payload 里取输入 ----
    # payload 是 JSON 字符串，包含 API 调用方传的参数
    if event_name == "repository_dispatch" and payload:
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            data = {}
        # 用 payload 的值覆盖 UI 输入（API 触发时没有网页输入）
        ui_source = data.get("source", ui_source)
        ui_ref = data.get("ref", ui_ref)
        ui_target = data.get("target", ui_target)
        ui_platform = data.get("platform", ui_platform)

    # ---- 3. 确定待导出项目 ----
    # 编译配置（workflow_build.json）从待导出项目读取
    if ui_project:
        project_repo, project_ref = parse_repo_ref(ui_project)
    else:
        project_repo, project_ref = current_repo, current_sha

    # ---- 4. 读取待导出项目的 workflow_build.json ----
    build_cfg_path = os.environ.get("BUILD_CONFIG", ".github/workflow_build.json")
    cfg_path = Path(build_cfg_path)
    # 待导出项目是远程仓库时，克隆它来读配置
    if project_repo != current_repo:
        temp_dir = os.environ.get("RUNNER_TEMP", "/tmp")
        clone_project(project_repo, project_ref, os.path.join(temp_dir, "proj_cfg"))
        cfg_path = Path(temp_dir) / "proj_cfg" / ".github" / "workflow_build.json"
    if not cfg_path.is_file():
        fail(f"缺少待导出项目的 .github/workflow_build.json: {cfg_path}")
    with cfg_path.open(encoding="utf-8") as f:
        config = json.load(f)

    # ---- 5. 确定引擎来源（source）----
    # UI 填了用 UI 的；没填用配置文件里的（默认官方 master）
    source = ui_source or config.get("source", "godotengine/godot@master")
    engine_repo, config_ref = parse_repo_ref(source)

    # ---- 6. 确定引擎引用（ref）----
    # 优先级：UI > source 里的 @ref > 默认 master
    engine_ref = ui_ref or config_ref or "master"

    # ---- 7. 确定构建目标（target）----
    # UI 逗号串取第一个；否则从配置 target 数组取第一个（一次只编译一个）
    target = ""
    if ui_target:
        target_list = [t.strip() for t in ui_target.split(",") if t.strip()]
        target = target_list[0] if target_list else ""
    else:
        targets = config.get("target", [])
        target = targets[0] if targets else ""
    if not target:
        fail("未解析到 target")
    if target not in ("editor", "template_debug", "template_release"):
        fail(f"unsupported target '{target}'")

    # ---- 8. 确定平台列表（platform）----
    # UI 逗号串；否则从配置 platform 数组读取。输出成 JSON 数组供矩阵使用
    platform_row = ui_platform or " ".join(config.get("platform", []))
    if not platform_row:
        fail("未解析到 platform")
    # 兼容逗号或空格分隔，拆成列表
    platforms = [p.strip() for p in platform_row.replace(",", " ").split() if p.strip()]
    allowed_platforms = {"linux", "windows", "macos", "android", "ios", "visionos", "web"}
    for platform in platforms:
        if platform not in allowed_platforms:
            fail(f"unsupported platform '{platform}'")
    platforms_json = json.dumps(platforms)  # 转成 JSON 数组字符串

    # ---- 9. 确定编译配置来源（profile/gdbuild）----
    # UI 传了用 UI 的；否则用配置文件 profile_path/gdbuild_path 指定的路径（默认 build/ 下）
    # 生成 repo: 形式 = 让 godot-config-inject 从待导出项目仓库里取这个文件
    profile_rel = config.get("profile_path", "build/profile.py")
    gdbuild_rel = config.get("gdbuild_path", "build/project.gdbuild")
    profile = ui_profile or f"repo:{project_repo}@{project_ref}:{profile_rel.strip('/')}"
    gdbuild = ui_gdbuild or f"repo:{project_repo}@{project_ref}:{gdbuild_rel.strip('/')}"

    # 自定义模块列表
    custom_modules = config.get("custom_modules", [])
    custom_modules_str = ",".join(custom_modules) if isinstance(custom_modules, list) else str(custom_modules)
    upload = config.get("upload_artifact", True)

    # ---- 10. 解析引擎 SHA + 仓库安全名 ----
    engine_sha = resolve_engine_sha(engine_repo, engine_ref)
    repo_safe = engine_repo.replace("/", "_")

    # ---- 11. 输出所有参数到 $GITHUB_OUTPUT ----
    output_lines = [
        ("platforms", platforms_json),       # 平台 JSON 数组（矩阵用）
        ("repository", engine_repo),         # 引擎仓库
        ("repo-safe", repo_safe),            # 仓库安全名
        ("ref", engine_ref),                 # 引擎引用
        ("engine-sha", engine_sha),          # 引擎 commit SHA（缓存 key）
        ("engine-version", engine_ref),      # 引擎版本
        ("target", target),                  # 构建目标
        ("profile", profile),                # SCons 配置来源
        ("gdbuild", gdbuild),                # .gdbuild 配置来源
        ("custom-modules", custom_modules_str),  # 自定义模块
        ("upload-artifact", str(upload).lower()),  # 是否上传
    ]
    output_path = os.environ.get("GITHUB_OUTPUT", "")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as f:
            for key, value in output_lines:
                f.write(f"{key}={value}\n")
    for key, value in output_lines:
        print(f"{key}={value}")
    print(f"repo={engine_repo} ref={engine_ref} target={target} platforms={platforms_json}")


# ============================================================
# 程序入口
# ============================================================
if __name__ == "__main__":
    main()

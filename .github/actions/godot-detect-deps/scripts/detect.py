#!/usr/bin/env python3
"""检测本次构建需要哪些可选的 Godot 依赖。

读取解析出的 SCons ``profile.py`` 与用户提供的 ``scons-flags``，
逐行输出每个可选依赖对应的 ``need-<flag>=yes|no``。

有效值优先级（与 scons 实际接收的保持一致）：
  * profile.py 中显式 ``flag="no"``     -> 不需要
  * scons-flags 中 ``flag=yes|no``      -> 覆盖 profile.py（用户显式意图）
  * 各处均未出现                        -> 使用各标志默认值（见 FLAGS）

各标志默认值：渲染 / SDK 相关（d3d12, angle, winrt, accesskit, vulkan）默认
为 "yes"，确保绝不跳过构建可能需要的 SDK；``use_mingw`` 默认为 "no"，因为
MSVC 是 Windows 默认编译器，仅显式要求时才准备 POSIX 线程版 MinGW。

只解析 ``flag = "value"`` 形式的赋值行；两个文件都不会被执行。
"""
import re
import sys

# 配置键 -> (输出名, 默认值)
FLAGS = {
    "d3d12":     ("d3d12",     "yes"),
    "angle":     ("angle",     "yes"),
    "winrt":     ("winrt",     "yes"),
    "accesskit": ("accesskit", "yes"),
    "vulkan":    ("vulkan",    "yes"),
    "use_mingw": ("mingw",     "no"),
}
# profile.py:  flag = "value"
_PROFILE_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*=\s*"([^"]*)"', re.M)
# scons-flags: 词边界 flag=yes|no（最后一次出现生效）
_SCONS_RE = re.compile(r'(?<![A-Za-z0-9_])([A-Za-z_]\w*)\s*=\s*(yes|no)\b', re.I)


def main() -> int:
    profile_path = sys.argv[1] if len(sys.argv) > 1 else ""
    scons_flags = sys.argv[2] if len(sys.argv) > 2 else ""

    values: dict[str, str] = {}

    # 1) profile.py —— 基础层
    if profile_path:
        try:
            with open(profile_path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            text = ""  # 读不了则回退到各标志默认值
        for match in _PROFILE_RE.finditer(text):
            values[match.group(1)] = match.group(2).strip().lower()

    # 2) scons-flags —— 用户显式意图，覆盖 profile.py（后写覆盖先写）
    if scons_flags:
        for match in _SCONS_RE.finditer(scons_flags):
            values[match.group(1)] = match.group(2).strip().lower()

    for key, (out, default) in FLAGS.items():
        needed = "no" if values.get(key, default) == "no" else "yes"
        print(f"need-{out}={needed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

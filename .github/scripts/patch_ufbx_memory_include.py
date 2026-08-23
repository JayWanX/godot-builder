#!/usr/bin/env python3
"""Guard unconditional `#include <memory>` in thirdparty/ufbx/ufbx.h.

Some engine source snapshots place `#include <memory>` at the top level of
ufbx.h (not inside an `#if defined(__cplusplus)` block). Because ufbx.c is
compiled as C, the C driver does not add C++ standard-library headers to the
include path, so `#include <memory>` fails with `fatal error: memory: No such
file or directory` (other C++ translation units still compile fine). This
script wraps such an unconditional include with `#if defined(__cplusplus)` /
`#endif` so it is only pulled in for C++ builds. Idempotent: already guarded or
guardless files are left untouched.

Only ufbx.h is patched to keep the scope minimal; headers that already guard
`<memory>` (e.g. current upstream) are never modified.

Usage:
    python patch_ufbx_memory_include.py [ROOT]

ROOT defaults to the current directory.
"""

import os
import re
import sys

TARGET_REL = os.path.join("thirdparty", "ufbx", "ufbx.h")
MEMORY_INCLUDE_RE = re.compile(r'^\s*#\s*include\s*[<"]memory[>"]')
COND_RE = re.compile(r"^\s*#\s*if(?:def|ndef)?\b")
ENDIF_RE = re.compile(r"^\s*#\s*endif\b")
BOM = b"\xef\xbb\xbf"


def wrap_unconditional_memory(text):
    """Wrap every unconditional (depth-0) `<memory>` include in `#if`.

    [return] 修改后的文本；若没有需要包裹的 include 则返回 None。
    """
    lines = text.split("\n")
    depth = 0
    result = []
    patched = False
    for line in lines:
        stripped = line.strip()
        if MEMORY_INCLUDE_RE.match(stripped) and depth == 0:
            indent = line[: len(line) - len(line.lstrip())]
            result.append(f"{indent}#if defined(__cplusplus)")
            result.append(line)
            result.append(f"{indent}#endif")
            patched = True
            continue
        if COND_RE.match(stripped):
            depth += 1
        elif ENDIF_RE.match(stripped):
            depth = max(0, depth - 1)
        result.append(line)
    return "\n".join(result) if patched else None


def main():
    """定位 ufbx.h 并应用补丁，输出 GitHub Actions 可识别的标记。"""
    root = "."
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        root = sys.argv[1]
    target = os.path.join(root, TARGET_REL)
    if not os.path.isfile(target):
        print(f"::notice::ufbx.h 不存在，跳过：{target}")
        return 0
    with open(target, "rb") as fh:
        data = fh.read()
    bom = data.startswith(BOM)
    if bom:
        data = data[len(BOM):]
    text = data.decode("utf-8")
    updated = wrap_unconditional_memory(text)
    if updated is None:
        print(f"::notice::{target} 无无条件 #include <memory>，未改动。")
        return 0
    with open(target, "wb") as fh:
        fh.write((BOM if bom else b"") + updated.encode("utf-8"))
    print(f"::notice::已将 {target} 的 #include <memory> 用 __cplusplus 条件包裹。")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""Insert missing standard-library includes for newer toolchains.

Newer compilers dropped transitive includes (e.g. <memory> via <thread>), so
files using std::unique_ptr / std::unique_lock / pthread_* without the defining
header fail to compile. This script adds the needed headers based on the types
actually used. Idempotent: already self-contained files are left untouched.

Usage:
    python ensure_standard_includes.py [ROOT] [--dry-run]
"""

import os
import re
import sys

HEADER_FAMILIES = (
    ("memory", re.compile(r"\bstd::(?:make_)?(?:unique_ptr|shared_ptr|weak_ptr|enable_shared_from_this|allocator|addressof)\b")),
    ("mutex", re.compile(r"\bstd::(?:unique_lock|scoped_lock|lock_guard)\b")),
    ("pthread.h", re.compile(r"\bpthread_t\b|\bpthread_[a-z_]+_t\b|\bpthread_[a-z_]+(?=\()")),
)

SKIP_DIRS = {".git", "bin", ".scons_cache"}
EXTS = (".cpp", ".h", ".hpp", ".cc", ".cxx", ".mm", ".c")


def has_include(text, header):
    return re.search(r"^\s*#\s*include\s*<\s*" + re.escape(header) + r"(?:\.[a-zA-Z0-9_]+)?>", text, re.M) is not None


def find_include_insert_index(lines):
    """Index AFTER which to insert a new ``#include``.

    Insert after the last ``#include`` at the shallowest preprocessor depth, so
    the new include lands in the common (always-compiled) section rather than
    inside a platform/feature ``#ifdef`` the target may skip — e.g.
    ``thread_posix.cpp`` ends with ``<pthread_np.h>`` under
    ``#ifdef PTHREAD_BSD_SET_NAME``, which is excluded on Linux.

    Returns ``None`` if the file has no ``#include``.
    """
    depth = 0
    include_positions = []  # (line_index, nesting_depth)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r"^\s*#\s*if(?:def|ndef)?\b", stripped):
            depth += 1
        elif re.match(r"^\s*#\s*endif\b", stripped):
            depth = max(0, depth - 1)
        # #else / #elif keep the same depth.
        if re.match(r"^\s*#\s*include\b", line):
            include_positions.append((i, depth))
    if not include_positions:
        return None
    min_depth = min(d for _, d in include_positions)
    # Last ``#include`` at the shallowest depth.
    return max(i for i, d in include_positions if d == min_depth)


def insert_after_last_include(text, headers, eol):
    lines = text.split(eol)
    idx = find_include_insert_index(lines)
    if idx is None:
        return None
    for header in headers:
        lines.insert(idx + 1, f"#include <{header}>")
        idx += 1
    return eol.join(lines)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    root = args[0] if args else "."
    dry_run = "--dry-run" in sys.argv

    patched = 0
    no_include = 0
    not_utf8 = 0
    for cur, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for name in files:
            if not name.endswith(EXTS):
                continue
            path = os.path.join(cur, name)
            try:
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                not_utf8 += 1
                continue
            needed = [header for header, pattern in HEADER_FAMILIES if pattern.search(text) and not has_include(text, header)]
            if not needed:
                continue
            eol = "\r\n" if b"\r\n" in data else "\n"
            updated = insert_after_last_include(text, needed, eol)
            if updated is None:
                no_include += 1
                continue
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            print(("DRY-RUN " if dry_run else "") + rel + "  + " + ", ".join("<" + h + ">" for h in needed))
            patched += 1
            if not dry_run:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(updated)
    print(f"patched files: {patched}, skipped (no include line): {no_include}, skipped (not utf-8): {not_utf8}")


if __name__ == "__main__":
    main()
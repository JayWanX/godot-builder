#!/usr/bin/env python3
"""Insert missing standard-library includes for newer toolchains.

Newer compilers dropped transitive includes (e.g. <memory> via <thread>), so
files using std::unique_ptr / std::unique_lock / pthread_* without the defining
header fail to compile. This script adds the needed headers based on the types
actually used. Idempotent: already self-contained files are left untouched.

Platform applicability: each rule declares the platforms it applies to
("all" / "posix" / "windows"). POSIX-only headers (e.g. <pthread.h>) are never
injected when targeting Windows (MSVC has no pthread.h), even if the symbol
appears inside a platform-conditional block such as zstd's threading.c.

Edge-case handling:
- Mixed line endings: files are split on "\\n" only, so "\\r" stays attached to
  each line and the original byte layout is preserved on write-back.
- UTF-8 BOM: stripped before matching and restored on write-back.
- Conditional includes (#if/#ifdef blocks) do not count as "already included":
  the patch must land in the always-compiled section to work on every target.

Usage:
    python ensure_standard_includes.py [ROOT] [--dry-run] [--platform posix|windows]
"""

import os
import re
import sys

# (header, platforms, pattern)  -- platforms: {"all"} | {"posix"} | {"windows"}
HEADER_FAMILIES = (
    ("memory", {"all"}, re.compile(r"\bstd::(?:make_)?(?:unique_ptr|shared_ptr|weak_ptr|enable_shared_from_this|allocator|addressof)\b")),
    ("mutex", {"all"}, re.compile(r"\bstd::(?:unique_lock|scoped_lock|lock_guard)\b")),
    ("pthread.h", {"posix"}, re.compile(r"\bpthread_t\b|\bpthread_[a-z_]+_t\b|\bpthread_[a-z_]+(?=\()")),
    ("sal.h", {"all"}, re.compile(r"\b_In_count_\b|\b_In_opt_count_\b")),
)

SKIP_DIRS = {".git", "bin", ".scons_cache"}
EXTS = (".cpp", ".h", ".hpp", ".cc", ".cxx", ".mm", ".c")
BOM = b"\xef\xbb\xbf"

_COND_RE = re.compile(r"^\s*#\s*if(?:def|ndef)?\b")
_ENDIF_RE = re.compile(r"^\s*#\s*endif\b")
_INCLUDE_RE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]')


def is_applicable(family, platform):
    """Whether a rule applies to the target platform."""
    return "all" in family[1] or platform in family[1]


def parse_args(argv):
    """Parse CLI args; returns (root, dry_run, platform).

    ``platform`` is the compile target ("posix" | "windows"); defaults to the
    host OS when not given explicitly.
    """
    dry_run = False
    platform = None
    positional = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--dry-run":
            dry_run = True
        elif a == "--platform":
            if i + 1 >= len(argv):
                print("::error::--platform requires a value (posix|windows).")
                sys.exit(1)
            platform = argv[i + 1]
            i += 1
        elif a.startswith("-"):
            print(f"::error::unknown option {a}")
            sys.exit(1)
        else:
            positional.append(a)
        i += 1
    if platform is None:
        platform = "windows" if os.name == "nt" else "posix"
    if platform not in ("posix", "windows"):
        print(f"::error::unsupported platform '{platform}', expected posix or windows.")
        sys.exit(1)
    root = positional[0] if positional else "."
    return root, dry_run, platform


def scan_includes(lines):
    """Scan preprocessor structure; returns [(depth, header, line_index), ...].

    Tracks ``#if/#ifdef/#ifndef/#endif`` nesting so callers can tell
    unconditional includes (depth 0) from conditional ones. ``#else`` and
    ``#elif`` keep the current depth.
    """
    depth = 0
    result = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if _COND_RE.match(stripped):
            depth += 1
        elif _ENDIF_RE.match(stripped):
            depth = max(0, depth - 1)
        m = _INCLUDE_RE.match(stripped)
        if m:
            result.append((depth, m.group(1), i))
    return result


def has_include(includes, header):
    """True if ``header`` is included at depth 0 (unconditional section).

    Includes inside ``#if``/``#ifdef`` blocks do not count: the injected patch
    must land in the always-compiled section to be effective on every target.
    """
    return any(depth == 0 and name == header for depth, name, _ in includes)


def find_include_insert_index(includes):
    """Index AFTER which to insert a new ``#include``.

    Prefer the last ``#include`` at depth 0 (unconditional section) so the new
    include lands in the common, always-compiled section rather than inside a
    platform/feature ``#ifdef`` the target may skip — e.g. ``thread_posix.cpp``
    ends with ``<pthread_np.h>`` under ``#ifdef PTHREAD_BSD_SET_NAME``, which
    is excluded on Linux. When no unconditional include exists, fall back to
    the file top (``-1``, before any ``#if`` block, hence depth 0) so the patch
    actually takes effect; ``has_include`` and this index stay consistent.

    Returns ``None`` if the file has no ``#include``.
    """
    if not includes:
        return None
    depth0 = [i for d, _, i in includes if d == 0]
    if depth0:
        return max(depth0)
    return -1


def insert_after_last_include(text, headers):
    lines = text.split("\n")
    includes = scan_includes(lines)
    idx = find_include_insert_index(includes)
    if idx is None:
        return None
    # Match the file's line-ending style (first line when inserting at top).
    crlf = lines[idx].endswith("\r") if idx >= 0 else lines[0].endswith("\r")
    for header in headers:
        lines.insert(idx + 1, f"#include <{header}>" + ("\r" if crlf else ""))
        idx += 1
    return "\n".join(lines)


def main():
    root, dry_run, platform = parse_args(sys.argv[1:])
    families = [f for f in HEADER_FAMILIES if is_applicable(f, platform)]

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
            except OSError as e:
                print(f"::warning::{path}: cannot read ({e})")
                continue
            bom = data.startswith(BOM)
            if bom:
                data = data[len(BOM):]
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                not_utf8 += 1
                continue
            needed = [header for header, _, pattern in families if pattern.search(text)]
            if not needed:
                continue
            includes = scan_includes(text.split("\n"))
            needed = [header for header in needed if not has_include(includes, header)]
            if not needed:
                continue
            updated = insert_after_last_include(text, needed)
            if updated is None:
                no_include += 1
                continue
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            print(("DRY-RUN " if dry_run else "") + rel + "  + " + ", ".join("<" + h + ">" for h in needed))
            patched += 1
            if not dry_run:
                with open(path, "wb") as fh:
                    fh.write((BOM if bom else b"") + updated.encode("utf-8"))
    print(f"patched files: {patched}, skipped (no include line): {no_include}, skipped (not utf-8): {not_utf8}")


if __name__ == "__main__":
    main()

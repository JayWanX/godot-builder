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

C++-only header guarding: standard-library headers that exist only in C++
(`<memory>`, `<mutex>`) must not be pulled into translation units compiled as C
(e.g. thirdparty/ufbx/ufbx.c), where the C driver has no C++ include path.
Headers that are compiled as C are detected by a same-named sibling `.c` file
(next to ufbx.h sits ufbx.c). Any unconditional (depth-0) include of a
CXX_ONLY_HEADERS member in such a header is wrapped in
`#if defined(__cplusplus)` / `#endif`; this is not part of HEADER_FAMILIES
because the fix is a guard, not an addition.

Comment/string stripping: HEADER_FAMILIES patterns are matched against a copy
of each file with comments and string/char literals blanked out, so
identifiers that appear only in documentation (e.g. std::unique_ptr in ufbx.h
doc comments) never trigger a spurious include.

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
HEADER_EXTS = (".h", ".hpp")
BOM = b"\xef\xbb\xbf"
# C++-only standard headers; unconditional includes need a __cplusplus guard.
CXX_ONLY_HEADERS = {"memory", "mutex"}

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


def insert_after_last_include(text, headers, guard_headers=frozenset()):
    lines = text.split("\n")
    includes = scan_includes(lines)
    idx = find_include_insert_index(includes)
    if idx is None:
        return None
    # Match the file's line-ending style (first line when inserting at top).
    crlf = lines[idx].endswith("\r") if idx >= 0 else lines[0].endswith("\r")
    eol = "\r" if crlf else ""
    for header in headers:
        if header in guard_headers:
            lines.insert(idx + 1, f"#if defined(__cplusplus)" + eol)
            lines.insert(idx + 2, f"#include <{header}>" + eol)
            lines.insert(idx + 3, f"#endif" + eol)
            idx += 3
        else:
            lines.insert(idx + 1, f"#include <{header}>" + eol)
            idx += 1
    return "\n".join(lines)


def guard_cxx_only_includes(text, headers):
    """Wrap every unconditional (depth-0) include of a C++-only header in `#if defined(__cplusplus)`.

    [param] headers 需要门控的 C++ 标准库专用头名集合。
    [return] 有门控时返回 (修改后的文本, 已门控的头名集合)，否则返回 None。
    """
    lines = text.split("\n")
    depth = 0
    result = []
    guarded = set()
    for line in lines:
        stripped = line.strip()
        m = _INCLUDE_RE.match(stripped)
        if m and depth == 0 and m.group(1) in headers:
            indent = line[: len(line) - len(line.lstrip())]
            result.append(f"{indent}#if defined(__cplusplus)")
            result.append(line)
            result.append(f"{indent}#endif")
            guarded.add(m.group(1))
            continue
        if _COND_RE.match(stripped):
            depth += 1
        elif _ENDIF_RE.match(stripped):
            depth = max(0, depth - 1)
        result.append(line)
    return ("\n".join(result), guarded) if guarded else None


def _blank_preserving_newlines(segment):
    """Return `segment` with every char except newlines replaced by a space."""
    return "".join("\n" if ch == "\n" else " " for ch in segment)


def strip_comments_and_strings(text):
    """Blank out comments and string/char literals, keeping newlines.

    Returns a copy where `//` and `/* */` comments and `"..."` / `'...'`
    literals are replaced by spaces, so HEADER_FAMILIES patterns only match
    real code, not documentation or string content.
    """
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "/" and nxt == "/":
            j = text.find("\n", i)
            if j == -1:
                out.append(_blank_preserving_newlines(text[i:]))
                break
            out.append(_blank_preserving_newlines(text[i:j]))
            i = j
        elif ch == "/" and nxt == "*":
            j = text.find("*/", i + 2)
            if j == -1:
                out.append(_blank_preserving_newlines(text[i:]))
                break
            out.append(_blank_preserving_newlines(text[i:j + 2]))
            i = j + 2
        elif ch in ('"', "'"):
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == ch:
                    j += 1
                    break
                j += 1
            out.append(_blank_preserving_newlines(text[i:j]))
            i = j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def main():
    root, dry_run, platform = parse_args(sys.argv[1:])
    families = [f for f in HEADER_FAMILIES if is_applicable(f, platform)]

    patched = 0
    guarded = 0
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
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            changed = False
            guarded_headers = set()
            # Only guard headers that may be compiled as C: those with a same-named
            # sibling `.c` file in the same directory (e.g. ufbx.h next to ufbx.c).
            is_c_header = name.endswith(HEADER_EXTS) and os.path.isfile(
                os.path.join(cur, os.path.splitext(name)[0] + ".c"))
            if is_c_header:
                guard = guard_cxx_only_includes(text, CXX_ONLY_HEADERS)
                if guard is not None:
                    text, guarded_headers = guard
                    print(("DRY-RUN " if dry_run else "") + rel + "  guard C++-only include(s) with __cplusplus")
                    guarded += 1
                    changed = True
            # Match against a copy with comments/strings blanked so identifiers
            # mentioned only in documentation never trigger a spurious include.
            code_only = strip_comments_and_strings(text) if families else ""
            needed = [header for header, _, pattern in families if pattern.search(code_only)]
            # Guarded headers already satisfy C++ builds; skip re-inserting them.
            needed = [header for header in needed if header not in guarded_headers]
            if needed:
                includes = scan_includes(text.split("\n"))
                needed = [header for header in needed if not has_include(includes, header)]
                if needed:
                    guard_inject = CXX_ONLY_HEADERS if is_c_header else frozenset()
                    updated = insert_after_last_include(text, needed, guard_inject)
                    if updated is not None:
                        text = updated
                        print(("DRY-RUN " if dry_run else "") + rel + "  + " + ", ".join("<" + h + ">" for h in needed))
                        patched += 1
                        changed = True
                    else:
                        no_include += 1
            if changed and not dry_run:
                with open(path, "wb") as fh:
                    fh.write((BOM if bom else b"") + text.encode("utf-8"))
    print(f"patched files: {patched}, guarded C++-only: {guarded}, skipped (no include line): {no_include}, skipped (not utf-8): {not_utf8}")


if __name__ == "__main__":
    main()

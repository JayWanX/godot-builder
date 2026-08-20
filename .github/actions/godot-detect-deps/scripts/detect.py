#!/usr/bin/env python3
"""Emit which optional Godot build dependency SDKs are needed.

Reads the resolved SCons ``profile.py`` AND any user-supplied ``scons-flags``,
and prints, one per line, ``need-<flag>=yes|no`` for each supported optional
dependency flag.

Effective value precedence (matches what scons actually receives):
  * an explicit ``flag="no"`` in profile.py  -> not needed
  * a ``flag=yes|no`` in scons-flags          -> overrides profile.py (explicit user intent)
  * flag absent everywhere                    -> needed (yes, safe default)

To stay safe we NEVER skip an SDK the build might need: scons-flags is treated
as authoritative, so the only way to get ``need=no`` is for the effective value
to be explicitly ``"no"``. profile-path empty/unreadable -> all needed (safe
default).

This gates SDK download steps so feature toggles are NEVER forced onto the scons
command line (which would silently override the user's profile). Only assignment
lines of the form ``flag = "value"`` are parsed; neither file is executed.
"""
import re
import sys

FLAGS = ("d3d12", "angle", "winrt", "accesskit", "vulkan")
# profile.py:  flag = "value"
_PROFILE_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*=\s*"([^"]*)"', re.M)
# scons-flags: word-boundary flag=yes|no  (last occurrence wins)
_SCONS_RE = re.compile(r'(?<![A-Za-z0-9_])([A-Za-z_]\w*)\s*=\s*(yes|no)\b', re.I)


def main() -> int:
    profile_path = sys.argv[1] if len(sys.argv) > 1 else ""
    scons_flags = sys.argv[2] if len(sys.argv) > 2 else ""

    values: dict[str, str] = {}

    # 1) profile.py -- base layer
    if profile_path:
        try:
            with open(profile_path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            text = ""  # unreadable -> fall back to safe "needed" default
        for match in _PROFILE_RE.finditer(text):
            values[match.group(1)] = match.group(2).strip().lower()

    # 2) scons-flags -- explicit user intent, overrides profile.py (last wins)
    if scons_flags:
        for match in _SCONS_RE.finditer(scons_flags):
            values[match.group(1)] = match.group(2).strip().lower()

    for flag in FLAGS:
        needed = "no" if values.get(flag) == "no" else "yes"
        print(f"need-{flag}={needed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

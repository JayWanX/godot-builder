#!/bin/sh
# 从远程仓库拉取一个文件到目标路径。
# 用法: fetch_repo_file "<spec>" "<dest>"
#   spec = "<owner/repo>[@<ref>]:<path>"
fetch_repo_file() {
  spec="$1"
  dest="$2"
  path="${spec#*:}"
  reporef="${spec%%:*}"
  if [ -z "$path" ]; then
    echo "::error::repo: '$spec' 缺少文件路径。"
    exit 1
  fi
  case "$path" in
    *..*)
      echo "::error::repo: 路径 '$path' 非法（不得包含 '..'）。"
      exit 1
      ;;
  esac
  repo="${reporef%@*}"
  ref="${reporef#*@}"
  [ "$ref" = "$reporef" ] && ref=""
  case "$repo" in
    [A-Za-z0-9_]*/[A-Za-z0-9_.-]*);;
    *)
      echo "::error::repo: 仓库 '$repo' 格式非法，应为 owner/repo。"
      exit 1
      ;;
  esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  if [ -n "$ref" ]; then
    # git clone -b 不支持 commit SHA（仅分支名/标签名），
    # 改用 init + fetch --depth=1 + checkout，同时兼容 SHA / 分支 / 标签。
    git init --quiet "$tmp/src"
    git -C "$tmp/src" remote add origin "https://github.com/$repo"
    git -C "$tmp/src" fetch --depth=1 --quiet origin "$ref"
    git -C "$tmp/src" checkout --quiet FETCH_HEAD
  else
    git clone --depth=1 --quiet "https://github.com/$repo" "$tmp/src"
  fi
  if [ ! -f "$tmp/src/$path" ]; then
    echo "::error::repo: '$path' 在 $repo@${ref:-default} 中不存在。"
    exit 1
  fi
  cp "$tmp/src/$path" "$dest"
}
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
    git clone --depth=1 --quiet -b "$ref" "https://github.com/$repo" "$tmp/src"
  else
    git clone --depth=1 --quiet "https://github.com/$repo" "$tmp/src"
  fi
  if [ ! -f "$tmp/src/$path" ]; then
    echo "::error::repo: '$path' 在 $repo@${ref:-default} 中不存在。"
    exit 1
  fi
  cp "$tmp/src/$path" "$dest"
}
#!/bin/sh
# Fetch a file from a remote repository into a destination path.
# Usage: fetch_repo_file "<spec>" "<dest>"
#   spec = "<owner/repo>[@<ref>]:<path>"
fetch_repo_file() {
  spec="$1"
  dest="$2"
  path="${spec#*:}"
  reporef="${spec%%:*}"
  if [ -z "$path" ]; then
    echo "::error::repo: missing file path in '$spec'."
    exit 1
  fi
  case "$path" in
    *..*)
      echo "::error::repo: invalid path '$path' (must not contain '..')."
      exit 1
      ;;
  esac
  repo="${reporef%@*}"
  ref="${reporef#*@}"
  [ "$ref" = "$reporef" ] && ref=""
  case "$repo" in
    [A-Za-z0-9_]*/[A-Za-z0-9_.-]*);;
    *)
      echo "::error::repo: invalid repository '$repo', expected owner/repo."
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
    echo "::error::repo: file '$path' not found in $repo@${ref:-default}."
    exit 1
  fi
  cp "$tmp/src/$path" "$dest"
}
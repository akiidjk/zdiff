#!/usr/bin/env bash
# gen-corpus.sh <repo> [outdir] [n_commit]
set -uo pipefail
REPO="${1:?usage: gen-corpus.sh <repo> [outdir] [n_commit]}"
OUT="${2:-corpus}"
N="${3:-300}"
MAXB="${MAXB:-8192}"

mkdir -p "$OUT"
: > "$OUT/index.txt"
i=0
while read -r sha; do
  parent="$(git -C "$REPO" rev-parse -q --verify "${sha}^")" || continue
  while read -r f; do
    [ -z "$f" ] && continue
    p="$OUT/$(printf %05d "$i")"
    git -C "$REPO" show "${parent}:${f}" > "$p.a" 2>/dev/null || { rm -f "$p.a"; continue; }
    git -C "$REPO" show "${sha}:${f}"    > "$p.b" 2>/dev/null || { rm -f "$p.a" "$p.b"; continue; }
    if [ "$(stat -c%s "$p.a")" -gt "$MAXB" ] || [ "$(stat -c%s "$p.b")" -gt "$MAXB" ]; then
      rm -f "$p.a" "$p.b"; continue
    fi
    printf '%s\t%s\n' "$p.a" "$p.b" >> "$OUT/index.txt"
    i=$((i+1))
  done < <(git -C "$REPO" diff --name-only --diff-filter=M "$parent" "$sha")
done < <(git -C "$REPO" log --format=%H -n "$N")
echo "$i coppie in $OUT/"

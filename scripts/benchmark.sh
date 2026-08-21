#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIZE_MB="${BENCH_SIZE_MB:-10}"
RUNS="${BENCH_RUNS:-10}"
WARMUP="${BENCH_WARMUP:-3}"
RESULTS="${BENCH_RESULTS:-$ROOT/benchmark-results/$(date +%Y%m%d-%H%M%S)}"

command -v hyperfine >/dev/null || { echo "error: hyperfine is required" >&2; exit 1; }
command -v diff >/dev/null || { echo "error: GNU diff is required" >&2; exit 1; }
[[ "$SIZE_MB" =~ ^[0-9]+$ ]] && ((SIZE_MB >= 10 && SIZE_MB <= 100)) || {
    echo "error: BENCH_SIZE_MB must be between 10 and 100" >&2
    exit 1
}
[[ "$RUNS" =~ ^[1-9][0-9]*$ && "$WARMUP" =~ ^[0-9]+$ ]] || {
    echo "error: BENCH_RUNS must be positive and BENCH_WARMUP non-negative" >&2
    exit 1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/zdiff-bench.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$RESULTS" "$tmp/small"

zig build --build-file "$ROOT/build.zig" -Doptimize=ReleaseFast --prefix "$ROOT/zig-out"
ZDIFF="$ROOT/zig-out/bin/zdiff"

lines=$((SIZE_MB * 1024 * 1024 / 74))
awk -v n="$lines" 'BEGIN { for (i=0; i<n; i++) printf "%08d abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789\n", i }' > "$tmp/large.a"
awk -v n="$lines" 'BEGIN { for (i=0; i<n; i++) printf "%08d abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ %s\n", i, (i==10 || i==n/2 || i==n-10) ? "changed!" : "0123456789" }' > "$tmp/large.b"

awk 'BEGIN { for (i=0; i<2500; i++) printf "old-%06d-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i }' > "$tmp/different.a"
awk 'BEGIN { for (i=0; i<2500; i++) printf "new-%06d-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", i }' > "$tmp/different.b"

awk 'BEGIN { for (i=0; i<50000; i++) printf "%06d common line payload 0123456789abcdef\n", i }' > "$tmp/scattered.a"
awk 'BEGIN { for (i=0; i<50000; i++) printf "%06d %s line payload 0123456789abcdef\n", i, i%50==25 ? "changed" : "common" }' > "$tmp/scattered.b"

awk -v n="$lines" 'BEGIN { for (i=0; i<n; i++) printf "%08d abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ %s\n", i, i==n/2 ? "middle-aaa" : "same-lines" }' > "$tmp/trim.a"
awk -v n="$lines" 'BEGIN { for (i=0; i<n; i++) printf "%08d abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ %s\n", i, i==n/2 ? "middle-bbb" : "same-lines" }' > "$tmp/trim.b"

for i in $(seq 1 200); do
    awk -v changed=0 'BEGIN { for (j=0; j<20; j++) printf "%03d small payload %s\n", j, j==10 && changed ? "b" : "a" }' > "$tmp/small/$i.a"
    awk -v changed=1 'BEGIN { for (j=0; j<20; j++) printf "%03d small payload %s\n", j, j==10 && changed ? "b" : "a" }' > "$tmp/small/$i.b"
done

run_case() {
    local name="$1" old="$2" new="$3" old_q new_q zdiff_q gnu_cmd
    printf -v old_q '%q' "$old"
    printf -v new_q '%q' "$new"
    printf -v zdiff_q '%q' "$ZDIFF"
    gnu_cmd="diff -U 1 --color=always $old_q $new_q >/dev/null; status=\$?; [[ \$status -le 1 ]]"
    hyperfine --shell=bash --warmup "$WARMUP" --runs "$RUNS" \
        --export-json "$RESULTS/$name.json" \
        -n zdiff "$zdiff_q $old_q $new_q >/dev/null" \
        -n 'GNU diff' "$gnu_cmd"
    hyperfine --shell=bash --warmup "$WARMUP" --runs "$RUNS" \
        --export-json "$RESULTS/$name-memory.json" -n 'GNU diff' "$gnu_cmd"
}

run_case large-few-changes "$tmp/large.a" "$tmp/large.b"
run_case completely-different "$tmp/different.a" "$tmp/different.b"
run_case scattered-changes "$tmp/scattered.a" "$tmp/scattered.b"
run_case common-prefix-suffix "$tmp/trim.a" "$tmp/trim.b"

printf -v small_q '%q' "$tmp/small"
printf -v zdiff_q '%q' "$ZDIFF"
hyperfine --shell=bash --warmup "$WARMUP" --runs "$RUNS" \
    --export-json "$RESULTS/many-small-files.json" \
    -n zdiff "for old in $small_q/*.a; do $zdiff_q \"\$old\" \"\${old%.a}.b\" >/dev/null || exit; done" \
    -n 'GNU diff' "for old in $small_q/*.a; do diff -U 1 --color=always \"\$old\" \"\${old%.a}.b\" >/dev/null; status=\$?; [[ \$status -le 1 ]] || exit \$status; done"
hyperfine --shell=bash --warmup "$WARMUP" --runs "$RUNS" \
    --export-json "$RESULTS/many-small-files-memory.json" \
    -n 'GNU diff' "for old in $small_q/*.a; do diff -U 1 --color=always \"\$old\" \"\${old%.a}.b\" >/dev/null; status=\$?; [[ \$status -le 1 ]] || exit \$status; done"

printf 'Results: %s\n' "$RESULTS"

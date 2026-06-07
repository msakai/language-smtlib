#!/usr/bin/env bash
#
# Round-trip / idempotency check of the parser+printer against a corpus of
# `.smt2` files (e.g. the example/regression suites shipped with cvc5, opensmt,
# yices2, z3).  For each file it runs `language-smtlib-exe` (parse -> render)
# twice and compares the two renderings:
#
#   stage 1:  parse(src)  -> out1     (PARSE_FAIL   if the source does not parse)
#   stage 2:  parse(out1) -> out2     (REPRINT_FAIL if our own output does not parse)
#   compare:  out1 == out2 ?          (DIFF         if the rendering is not idempotent)
#
# The library contract is `parse . render == id`, of which a stable canonical
# rendering (out1 == out2) is a necessary consequence; a DIFF therefore flags a
# genuine parser/printer bug, while PARSE_FAIL just means the input is not
# standard SMT-LIB 2.7 (solver extensions, negative-test files, non-smt2 data).
#
# Usage:
#   scripts/roundtrip-check.sh [options] [PATH...]
#
#   PATH...        files and/or directories to scan (default: current directory);
#                  directories are searched recursively for *.smt2
#
# Options:
#   --build        run `stack build` before checking
#   --out DIR      write the failing-file lists into DIR:
#                    parse-fail.tsv   "<file>\t<first error line>"
#                    reprint-fail.txt one path per line
#                    diff.txt         one path per line
#   -h, --help     show this help
#
# Examples:
#   scripts/roundtrip-check.sh misc
#   scripts/roundtrip-check.sh --build --out /tmp/rt misc/cvc5 misc/z3

set -uo pipefail

build=0
outdir=""
paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --build) build=1; shift ;;
    --out)   outdir="${2:?--out needs a directory}"; shift 2 ;;
    -h|--help) sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do paths+=("$1"); shift; done ;;
    -*) echo "roundtrip-check.sh: unknown option: $1" >&2; exit 2 ;;
    *) paths+=("$1"); shift ;;
  esac
done
[ ${#paths[@]} -eq 0 ] && paths=(".")

if ! command -v stack >/dev/null 2>&1; then
  echo "roundtrip-check.sh: need stack on PATH" >&2
  exit 1
fi

if [ "$build" -eq 1 ]; then
  stack build
fi

# `language-smtlib-exe` is run via stack.  Resolve the built binary once rather
# than paying `stack exec` startup per file (there can be thousands); this is
# equivalent to invoking `stack exec -- language-smtlib-exe ...` on each file.
exe="$(stack exec -- sh -c 'command -v language-smtlib-exe' 2>/dev/null)"
if [ -z "${exe:-}" ] || [ ! -x "$exe" ]; then
  echo "roundtrip-check.sh: language-smtlib-exe not found; run with --build first" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

parse_fail="$tmp/parse-fail.tsv"
reprint_fail="$tmp/reprint-fail.txt"
diff_list="$tmp/diff.txt"
: > "$parse_fail"; : > "$reprint_fail"; : > "$diff_list"

total=0; ok=0
while IFS= read -r f; do
  total=$((total+1))
  if ! "$exe" "$f" > "$tmp/out1" 2> "$tmp/err1"; then
    msg="$(grep -E 'unexpected|expecting|unknown command|reserved word' "$tmp/err1" | head -2 | paste -sd' ' -)"
    [ -z "$msg" ] && msg="$(grep -vE '^\s*$' "$tmp/err1" | head -1)"
    printf '%s\t%s\n' "$f" "$msg" >> "$parse_fail"
    continue
  fi
  if ! "$exe" "$tmp/out1" > "$tmp/out2" 2> "$tmp/err2"; then
    printf '%s\n' "$f" >> "$reprint_fail"
    continue
  fi
  if ! cmp -s "$tmp/out1" "$tmp/out2"; then
    printf '%s\n' "$f" >> "$diff_list"
    continue
  fi
  ok=$((ok+1))
done < <(for p in "${paths[@]}"; do
           if [ -d "$p" ]; then find "$p" -name '*.smt2' -type f
           else printf '%s\n' "$p"; fi
         done | sort)

n_parse="$(wc -l < "$parse_fail" | tr -d ' ')"
n_reprint="$(wc -l < "$reprint_fail" | tr -d ' ')"
n_diff="$(wc -l < "$diff_list" | tr -d ' ')"

echo "==================== SUMMARY ===================="
printf 'total:        %s\n' "$total"
printf 'ok:           %s\n' "$ok"
printf 'parse_fail:   %s   (input is not standard SMT-LIB 2.7)\n' "$n_parse"
printf 'reprint_fail: %s   (BUG: our own output does not re-parse)\n' "$n_reprint"
printf 'diff:         %s   (BUG: rendering is not idempotent)\n' "$n_diff"

if [ -n "$outdir" ]; then
  mkdir -p "$outdir"
  cp "$parse_fail" "$outdir/parse-fail.tsv"
  cp "$reprint_fail" "$outdir/reprint-fail.txt"
  cp "$diff_list" "$outdir/diff.txt"
  echo "wrote failure lists to $outdir/"
fi

# Exit non-zero only on real bugs, so this can gate CI.
[ "$n_reprint" -eq 0 ] && [ "$n_diff" -eq 0 ]

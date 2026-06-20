#!/usr/bin/env bash
#
# Build the conformance checker (behind the `tools` cabal flag) and run it
# over a directory of benchmarks.  Thin convenience wrapper; see
# conformance/README.md for the full workflow.
#
# Usage:
#   scripts/run-conformance.sh [PATH...]        # default PATH: ./benchmarks
#   scripts/run-conformance.sh --limit 100 ./benchmarks
#
# Any extra arguments are forwarded to language-smtlib-conformance.

set -euo pipefail

args=("$@")
if [ ${#args[@]} -eq 0 ]; then
  args=("./benchmarks")
fi

if command -v stack >/dev/null 2>&1; then
  stack build --flag language-smtlib:tools
  exec stack exec --flag language-smtlib:tools language-smtlib-conformance -- "${args[@]}"
elif command -v cabal >/dev/null 2>&1; then
  cabal build -f tools language-smtlib-conformance
  exec cabal run -f tools language-smtlib-conformance -- "${args[@]}"
else
  echo "run-conformance.sh: need stack or cabal on PATH" >&2
  exit 1
fi

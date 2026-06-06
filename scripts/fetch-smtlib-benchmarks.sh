#!/usr/bin/env bash
#
# Fetch SMT-LIB / SMT-COMP benchmark archives from a Zenodo record, for use with
# the language-smtlib conformance checker (see conformance/README.md).
#
# The SMT-LIB benchmark collections are published on Zenodo as one zstd-compressed
# tar archive per logic (e.g. QF_BV.tar.zst).  Some known records:
#
#   non-incremental 2024 : 11061097   ( https://zenodo.org/records/11061097 )
#   non-incremental 2025 : 15493090   ( https://zenodo.org/records/15493090 )
#   incremental     2023 : 10607775   ( https://zenodo.org/records/10607775 )
#
# This script is generic: pass any record id with --record.  With no logic
# arguments it downloads every archive in the record; otherwise it downloads
# only the named logics (a subset).  Archives are extracted by default.
#
# NOTE: the data is large.  SMT-LIB archives have a very high compression ratio,
# so the extracted size can be tens to hundreds of GB.  Nothing here is committed
# to the repository (the default output directory ./benchmarks is gitignored).
#
# Examples:
#   scripts/fetch-smtlib-benchmarks.sh --record 11061097 --list
#   scripts/fetch-smtlib-benchmarks.sh --record 11061097 QF_BV QF_LIA
#   scripts/fetch-smtlib-benchmarks.sh --record 10607775 --out ./inc-benchmarks

set -euo pipefail

ZENODO_BASE="https://zenodo.org"
RECORD=""
OUTDIR="./benchmarks"
DO_LIST=0
DO_EXTRACT=1
LOGICS=()

prog="$(basename "$0")"

usage() {
  cat <<EOF
usage: $prog --record ID [OPTIONS] [LOGIC...]

Download SMT-LIB benchmark archives (*.tar.zst) from a Zenodo record.

Options:
  --record ID     Zenodo record id (required), e.g. 11061097
  --out DIR       output directory (default: ./benchmarks)
  --list          list the archives available in the record and exit
  --no-extract    download only, do not extract the .tar.zst archives
  -h, --help      show this help

Arguments:
  LOGIC...        names of logics to fetch (e.g. QF_BV).  Matched against the
                  archive file names in the record.  If omitted, all archives
                  in the record are downloaded.

Known record ids:
  non-incremental 2024 = 11061097    non-incremental 2025 = 15493090
  incremental     2023 = 10607775
EOF
}

die() { echo "$prog: error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --record)     RECORD="${2:-}"; shift 2 ;;
    --out)        OUTDIR="${2:-}"; shift 2 ;;
    --list)       DO_LIST=1; shift ;;
    --no-extract) DO_EXTRACT=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    --*)          die "unknown option: $1" ;;
    *)            LOGICS+=("$1"); shift ;;
  esac
done

[ -n "$RECORD" ] || { usage >&2; die "--record is required"; }
command -v curl >/dev/null 2>&1 || die "curl is required"

api_url="$ZENODO_BASE/api/records/$RECORD"

# Print the record's files as TAB-separated lines: "key<TAB>size<TAB>download_url".
# Uses jq if available, otherwise python3; one of them must be present.
list_files() {
  local json
  json="$(curl -fsSL --retry 4 --retry-delay 2 "$api_url")" \
    || die "failed to query Zenodo API: $api_url"

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r \
      '.files[] | [.key, (.size|tostring), .links.self] | @tsv'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for f in d.get("files", []):
    links = f.get("links", {})
    url = links.get("self") or links.get("download") or ""
    print("%s\t%s\t%s" % (f.get("key",""), f.get("size",""), url))
'
  else
    die "need jq or python3 to parse the Zenodo API response"
  fi
}

human_size() {
  # bytes -> human readable; falls back to raw on non-numeric input
  local b="$1"
  case "$b" in
    ''|*[!0-9]*) echo "$b"; return ;;
  esac
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB", u, " "); i=1;
    while (b>=1024 && i<5){ b/=1024; i++ }
    printf("%.1f %s", b, u[i])
  }'
}

# wants_file KEY -> 0 if it should be downloaded given the LOGICS filter.
wants_file() {
  local key="$1"
  # Only consider zstd tarballs.
  case "$key" in
    *.tar.zst) : ;;
    *)         return 1 ;;
  esac
  [ ${#LOGICS[@]} -eq 0 ] && return 0
  local base="${key%.tar.zst}"
  for l in "${LOGICS[@]}"; do
    if [ "$base" = "$l" ] || [ "$key" = "$l" ]; then return 0; fi
  done
  return 1
}

files="$(list_files)"
[ -n "$files" ] || die "no files found for record $RECORD"

if [ "$DO_LIST" -eq 1 ]; then
  echo "Archives in Zenodo record $RECORD:"
  printf '%s\n' "$files" | while IFS=$'\t' read -r key size _url; do
    printf '  %-32s %s\n' "$key" "$(human_size "$size")"
  done
  exit 0
fi

mkdir -p "$OUTDIR"
matched=0

while IFS=$'\t' read -r key size url; do
  wants_file "$key" || continue
  matched=$((matched + 1))
  dest="$OUTDIR/$key"
  : "${url:=$ZENODO_BASE/records/$RECORD/files/$key?download=1}"

  if [ -f "$dest" ]; then
    echo ">> $key already downloaded ($(human_size "$size")), skipping download"
  else
    echo ">> downloading $key ($(human_size "$size"))"
    # -C - resumes a partial download; --retry handles transient network errors.
    curl -fL --retry 4 --retry-delay 2 -C - -o "$dest" "$url" \
      || die "download failed: $key"
  fi

  if [ "$DO_EXTRACT" -eq 1 ]; then
    marker="$dest.extracted"
    if [ -f "$marker" ]; then
      echo "   already extracted, skipping"
    else
      echo "   extracting $key ..."
      if tar --help 2>/dev/null | grep -q -- '--zstd'; then
        tar --zstd -xf "$dest" -C "$OUTDIR"
      elif command -v zstd >/dev/null 2>&1; then
        zstd -dc "$dest" | tar -xf - -C "$OUTDIR"
      else
        die "cannot extract: need tar with --zstd support or the zstd tool"
      fi
      touch "$marker"
    fi
  fi
done <<< "$files"

if [ "$matched" -eq 0 ]; then
  die "no archives matched the requested logics: ${LOGICS[*]:-<all>}"
fi

echo "Done. Benchmarks are under: $OUTDIR"
if [ "$DO_EXTRACT" -eq 1 ]; then
  echo "Run the conformance checker, e.g.:"
  echo "  stack build --flag language-smtlib:conformance"
  echo "  stack exec language-smtlib-conformance -- $OUTDIR"
fi

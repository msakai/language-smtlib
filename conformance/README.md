# Conformance checker for external SMT-LIB benchmark suites

This directory contains `language-smtlib-conformance`, a stand-alone driver that
stress-tests the parser and printer against large, real-world SMT-LIB 2 benchmark
collections — in particular the SMT-LIB / SMT-COMP suites published on
[Zenodo](https://zenodo.org/).

It is **deliberately excluded from the normal build, test suite and CI**: the
benchmark data is huge (tens to hundreds of GB once extracted) and lives outside
the repository. The tool is only built when the `conformance` cabal flag is set,
and the benchmark data is never committed (the default download directory
`benchmarks/` is gitignored).

## What it checks

For every `.smt2` file it finds, the tool verifies the library's full
round-trip guarantee, one command at a time (streaming, so arbitrarily large
files use bounded memory):

1. read each command with the incremental handle reader
   (`Language.SMTLIB.Reader.Handle.readCommand`);
2. re-render it with `renderText`;
3. re-parse the rendered text with `parseCommand'`;
4. assert the re-parsed AST equals the original (modulo source spans, via
   `noAnn`).

Failures are classified as `parse`, `reparse`, `mismatch`, or `io`, and a
summary is printed. The process exits non-zero if any file failed.

## Workflow

```sh
# 1. Download benchmarks on your own machine (Zenodo is not reachable from CI).
#    List what a record contains:
scripts/fetch-smtlib-benchmarks.sh --record 11061097 --list

#    Fetch a subset (a few logics) or omit the logic names for the whole record:
scripts/fetch-smtlib-benchmarks.sh --record 11061097 QF_BV QF_LIA

# 2. Build the checker with the flag enabled:
stack build --flag language-smtlib:conformance
#    (with cabal:  cabal build -f conformance language-smtlib-conformance)

# 3. Run it over the downloaded files:
stack exec language-smtlib-conformance -- benchmarks/
```

Or use the convenience wrapper, which builds and runs in one step:

```sh
scripts/run-conformance.sh benchmarks/
```

### Known Zenodo records

| Collection                | Record id  | URL                                   |
| ------------------------- | ---------- | ------------------------------------- |
| non-incremental 2024      | `11061097` | <https://zenodo.org/records/11061097> |
| non-incremental 2025      | `15493090` | <https://zenodo.org/records/15493090> |
| incremental 2023          | `10607775` | <https://zenodo.org/records/10607775> |

Pass any record id to `--record`; the script reads the actual file list from the
Zenodo REST API, so newer releases work without code changes.

## Tool options

```
language-smtlib-conformance [OPTIONS] PATH...

  --limit N           process at most N files
  --show-failures N   print at most N failure detail lines (default 20)
  --quiet             only print the final summary
  -h, --help          show this help
```

A `PATH` may be a single `.smt2` file or a directory (scanned recursively).

## Notes & caveats

- The download script needs `curl` and either `jq` or `python3` (to read the
  Zenodo API), plus `tar --zstd` or the `zstd` tool to extract archives.
- Disk space and time: SMT-LIB archives have a very high compression ratio.
  Check the sizes with `--list` before downloading, and prefer a few logics.
- A benchmark the tool cannot parse or round-trip is itself the finding — that
  is exactly the kind of coverage gap this checker exists to surface.

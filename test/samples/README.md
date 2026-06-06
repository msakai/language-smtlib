# Test samples

SMT-LIB 2 sample scripts used by the test suite (`test/Spec.hs`) for the
parse / render idempotence checks.

Most `.smt2` files under `smt/` are copied from
[`toysolver`](https://github.com/msakai/toysolver) (`samples/smt/`) so that this
repository's test suite is self-contained.

The following files are derived from the
[SMT-LIB Standard, Version 2.7](https://smt-lib.org/) reference document and
exercise the 2.7 syntax additions:

- `figure-3.11-example-script.smt2` — the example script of Figure 3.11
  (linearised; expected solver responses kept as comments).
- `figure-3.12-example-script.smt2` — the example script of Figure 3.12
  (linearised, with the figure's `...` placeholders removed).
- `smtlib-2.7-lambda-define-const.smt2` — the `lambda` binder, `define-const`,
  the `->` map sort and the apply operator `_` (Section 3.10).
- `smtlib-2.7-declare-sort-parameter.smt2` — the `declare-sort-parameter`
  command (Section 4.2.3).
- `list-append-match.smt2` — the list append/length axioms with a polymorphic
  `par` datatype, `match`, and the `_` wildcard pattern.

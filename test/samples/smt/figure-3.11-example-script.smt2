; Example script from the SMT-LIB 2.7 Reference, Figure 3.11
; ("Example script (over two columns), with expected solver responses in
; comments").  The two columns are linearised here in reading order; the
; ';'-prefixed lines are the expected solver responses, kept as comments.

(set-option :print-success true)
; success
(set-info :smt-lib-version 2.7)
; success
(set-logic QF_LIA)
; success
(declare-const w Int)
; success
(declare-const x Int)
; success
(declare-const y Int)
; success
(declare-const z Int)
; success
(assert (> x y))
; success
(assert (> y z))
; success
(push 1)
(assert (> z x))
(check-sat)
; unsat
(get-info :all-statistics)
; (:time 0.01 :memory 0.2)
(pop 1)
(push 1)
(check-sat)
; sat
(exit)

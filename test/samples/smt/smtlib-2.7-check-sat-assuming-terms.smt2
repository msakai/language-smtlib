; SMT-LIB 2.7 generalised check-sat-assuming: assumptions may be arbitrary
; Bool terms, not only prop_literals (a symbol or (not symbol)).
(set-logic QF_UF)
(declare-fun a () Bool)
(declare-fun b () Bool)
(declare-fun c () Bool)
(assert (or a b c))
; arbitrary Bool terms as assumptions, plus an empty assumption list
(check-sat-assuming ((= a b) (not (and b c)) (or a (not c))))
(check-sat-assuming ())
(get-unsat-assumptions)

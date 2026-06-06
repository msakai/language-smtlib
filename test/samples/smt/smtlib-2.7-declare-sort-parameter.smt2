; SMT-LIB 2.7 Reference, Section 4.2.3: the declare-sort-parameter command.
;
; "(declare-sort-parameter s) adds global sort parameter s to the current
;  signature."  Sort parameters are treated as implicitly universally quantified
;  sort variables in each asserted formula (prenex / rank-1 polymorphism).

(set-info :smt-lib-version 2.7)

; Declare a global sort parameter X, then a polymorphic function over it.
(declare-sort-parameter X)
(declare-fun f (X) X)
(declare-const a X)

; X behaves as an implicitly universally quantified sort variable here.
(assert (= (f a) a))

(check-sat)
(exit)

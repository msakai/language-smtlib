; List append / length axioms from the SMT-LIB 2.7 Reference (the match section),
; demonstrating a polymorphic (par) datatype, the match binder, and the _
; wildcard pattern (new in 2.7).  Wrapped in a self-contained script: the List
; datatype and the append/length symbols are declared so the asserts parse.

(set-info :smt-lib-version 2.7)

; List is a polymorphic datatype with constructors "nil" and "cons".
(declare-datatype List
  (par (T) ((nil) (cons (head T) (tail (List T))))))

(declare-fun append ((List Int) (List Int)) (List Int))
(declare-fun length ((List Int)) Int)

; Axiom for list append : version 1
(assert
  (forall ((l1 (List Int)) (l2 (List Int)))
    (= (append l1 l2)
       (match l1 (
          (nil l2)
          ((cons h t) (cons h (append t l2))))))))

; Axiom for list append : version 2 (uses the _ wildcard pattern)
(assert
  (forall ((l1 (List Int)) (l2 (List Int)))
    (= (append l1 l2)
       (match l1 (
          ((cons h t) (cons h (append t l2)))
          (_ l2))))))

; Axiom for list length (uses _ as a bound variable inside a constructor pattern)
(assert
  (forall ((l (List Int)))
    (= (length l)
       (match l (
          (nil 0)
          ((cons _ t) (length t)))))))

(check-sat)
(exit)

; Examples from the SMT-LIB 2.7 Reference, Section 3.10 (Logic Declarations),
; illustrating the new 2.7 syntax: the -> map sort, the lambda binder, the
; define-const command, and the apply operator _.
;
; The PDF writes the conversions between a function symbol f of rank t1 t2 and a
; map of sort (-> t1 t2) as:
;     (define-const c_f (lambda ((x t1)) (f x)))
;     (define-fun f_c ((x t1)) t2 (_ e x))
; Here t1 = t2 = Int.  (define-const takes <symbol> <sort> <term>, so the map
; sort is given explicitly.)

(set-info :smt-lib-version 2.7)

; A function symbol of rank Int Int.
(declare-fun f (Int) Int)

; The corresponding map, of sort (-> Int Int), built with lambda and named with
; define-const.
(define-const c_f (-> Int Int) (lambda ((x Int)) (f x)))

; A map e, and the function obtained from it via the apply operator _.
(declare-const e (-> Int Int))
(define-fun f_c ((x Int)) Int (_ e x))

; -> is right-associative: (-> Int Int Int) abbreviates (-> Int (-> Int Int)).
(declare-const g (-> Int Int Int))

(exit)

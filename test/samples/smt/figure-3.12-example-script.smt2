; Example script from the SMT-LIB 2.7 Reference, Figure 3.12
; ("Another example script (excerpt), with expected solver responses in
; comments").  The two columns are linearised in reading order and the figure's
; "..." placeholders are dropped so the script is syntactically complete.
; The '@'-prefixed symbols are solver-generated abstract values, as in the PDF.

(set-info :smt-lib-version 2.7)
(set-option :produce-models true)
(declare-const x Int)
(declare-const y Int)
(declare-fun f (Int) Int)
(assert (= (f x) (f y)))
(assert (not (= x y)))
(check-sat)
; sat
(get-value (x y))
; ((x 0)
;  (y 1)
; )
(declare-const a (Array Int (List Int)))
(check-sat)
; sat
(get-value (a))
; ( (a (as @array1 (Array Int (List Int))))
; )
(get-value ((select @array1 2)))
; (((select (as @array1 (Array Int (List Int))) 2)
;   (as @list0 (List Int))
; )
; )
(get-value ((first @list0) (rest @list0)))
; (((first (as @list0 (List Int))) 1)
;  ((rest (as @list0 (List Int))) (as nil (List Int)))
; )

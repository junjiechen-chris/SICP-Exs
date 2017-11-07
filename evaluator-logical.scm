(define input-prompt ";;; Query input:")
(define output-prompt ";;; Query output:")
					;driver-loop and instantiate
(define (query-driver-loop)
  (prompt-for-input input-prompt)
  (let ((q (query-syntax-process (read))))
    (cond ((assertion-to-be-added? q)
	   (add-rule-or-assertion! (add-assertion-body q))
	   (newline)
	   (display "Assertion added to data base.")
	   (query-driver-loop))
	  (else
	   (newline)
	   (display output-prompt)
	   (display-stream
	    (stream-map
	     (lambda (frame)
	       (instantiate q frame (lambda (v f)
				      (contract-question-mark v))))
	     (qeval q (singleton-stream `()))))
	   (query-driver-loop)))))
(define (instantiate exp frame ubound-var-handler)
  (define (copy exp)
    (cond ((var? exp)
	   (let ((binding (binding-in-frame exp frame)))
	     (if binding
		 (copy (binding-value binding))
		 (unbound-var-handler exp frame))))
	  ((pair? exp)
	   (cons (copy (car exp)) (copy (cdr exp))))
	  (else exp)))
  (copy exp))

					;evaluator
(define (qeval query frame-stream)
  (let ((qproc (get (type query) `qeval)))
    (if qproc
	(qproc (contents query) frame-stream)
	(simple-query query frame-stream))))

(define (simple-query query-pattern frame-stream)
  (stream-flatmap
   (lambda (frame)
     (stream-append-delayed (find-assertions query-pattern frame)
			    (delay (apply-rules query-pattern frame))))
   frame-stream))


					;compound query
;;procedure for and
(define (conjoin conjuncts frame-stream)
  (if (empty-conjunction? conjuncts)
      frame-stream
      (conjoin (rest-conjuncts conjuncts)
	       (qeval (first-conjunct conjuncts)
		      frame-stream))))
;;procedure for or
(define (disjoin disjuncts frame-stream)
  (if (empty-disjunction? disjuncts)
      the-empty-stream
      (interleave-delayed
       (qeval (first-disjunct disjuncts) frame-stream)
       (delay (disjoin (rest-disjuncts disjuncts)
		       frame-stream)))))
;;procedure for not
(define (negate operands frame-stream)
  (stream-flatmap
   (lambda (frame)
     (if (stream-null? (qeval (negated-query operands)
			      (singleton-stream frame)))
	 (singleton-stream frame)
	 the-empty-stream))
   frame-stream))
;;procudre for lisp-value
(define (lisp-value call frame-stream)
  (stream-flatmap
   (lambda (frame)
     (if (execute (instantiate call frame (lambda (v f)
					    (error "Unknown pattern variable -- LISP-VALUE" v))))
	 (singleton-stream frame)
	 the-empty-frame))
   frame-stream))
;;execute system
(define (execute exp)
  (apply (eval (predicate exp) user-initial-environment)
	 (args exp)))
;;always-true inference
(define (always-true ignore frame-stream) frame-stream)

					;pattern matching
(define (find-assertion pattern frame)
  (stream-flatmap (lambda (datum) (check-an-assertion datum pattern frame))
		  (fetch-assertions pattern frame)))

(define (check-an-assertion assertion query-pat query-frame)
  (let ((match-result (pattern-match query-pat assertion query-frame)))
    (if (eq? match-result `failed)
	the-empty-stream
	(singleton-stream match-result))))
(define (pattern-match pat dat frame)
  (cond ((eq? frame `failed) `failed)
	((equal? pat dat) frame)
	((var? pat) (extend-if-consistent pat dat frame))
	((and (pair? pat) (pair? dat))
	 (pattern-match (cdr pat)
			(cdr dat)
			(pattern-match (car pat)
				       (car dat)
				       frame)))
	(else `failed)))
(define (extend-if-consistent var dat frame)
  (let ((binding (binding-in-frame var frame)))
    (if binding
	(pattern-match (binding-value binding) dat frame)
	(extend var dat frame))))

					;applying rule and unification
(define (apply-rules pattern frame)
  (stream-flatmap (lambda (rule)
		    (apply-a-rule rule pattern frame))
		  (fetch-rules pattern frame)))
(define (apply-a-rule rule query-pattern query-frame)
  (let ((clean-rule (rename-variables-in rule)))
    (let ((unify-result
	   (unify-match query-pattern
			(conslusion clean-rule)
			query-frame)))
      (if (eq? unify-result `failed)
	  the-empty-stream
	  (qeval (rule-body clean-rule)
		 (singleton-stream unify-result))))))
(define (rename-variable-in rule)
  (let ((rule-application-id (new-rule-application-id)))
    (define (tree-walk exp)
      (cond ((var? exp)
	     (make-new-variable exp rule-application-id))
	    ((pair? exp)
	     (cons (tree-walk (car exp))
		   (tree-walk (cdr exp))))
	    (else exp)))
    (tree-walk rule)))
(define (unify-match p1 p2 frame)
  (cond ((eq? frame `failed) `failed)
	((equal? p1 p2) frame)
	((var? p1) (extend-if-possible p1 p2 frame))
	((var? p2) (extend-if-possible p2 p1 frame)) ;***
	((and (pair? p1) (pair? p2))
	 (unify-match (cdr p1)
		      (cdr p2)
		      (unify-match (car p1)
				   (car p2)
				   frame)))
	(else `failed)))
(define (extend-if-possible var val frame)
  (let ((binding (binding-in-frame var frame)))
    (cond (binding
	   (unify-match
	    (binding-value binding) val frame))
	  ((var? val);***
	   (let ((binding (binding-in-frame val frame)))
	     (if binding
		 (unify-match
		  var (binding-value binding) frame)
		 (extend var val frame))))
	  ((depends-on? val var frame);***
	   `failed)
	  (else (extend var val frame)))))
(define (depends-on? exp var frame)
  (define (tree-walk e)
    (cond ((var e)
	   (if (equal? var e)
	       true
	       (let ((b (binding-in-frame e frame)))
		 (if b
		     (tree-walk (binding-value b))
		     false))))
	  ((pair? e)
	   (or (tree-walk (car e))
	       (tree-walk (cdr e))))
	  (else false)))
  (tree-walk exp))


					;expression setting
(put `and `qeval conjoin)
(put `or `qeval disjoin)
(put `not `qeval negate)
(put `always-true `qeval always-true)
(put `lisp-value `qeval lisp-value)

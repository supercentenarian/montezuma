(in-package #:montezuma)


(defun string-scanner (regexp string)
  (let ((start 0))
    #'(lambda ()
	(multiple-value-bind (match-start match-end)
	    (cl-ppcre:scan regexp string :start start)
	  (if (null match-start)
	      nil
	      (progn
		(setq start (if (= match-start match-end)
				(1+ match-end)
				match-end))
		(values (subseq string match-start match-end) match-start match-end)))))))
	

(defclass tokenizer (token-stream)
  ((input :initarg :input)))

(defmethod close-stream ((self tokenizer))
  (with-slots (input) self
    (when (streamp input)
      (close input))))



(defclass regexp-tokenizer (tokenizer)
  (string-scanner))

(defmethod initialize-instance :after ((self regexp-tokenizer) &key)
  (with-slots (string-scanner input) self
    (let ((input-string (if (streamp input) (stream-contents input) input)))
      (setf string-scanner (string-scanner (token-regexp self) input-string)))))

(defmethod next-token ((self regexp-tokenizer))
  (with-slots (string-scanner) self
    (multiple-value-bind (term start end)
	(funcall string-scanner)
      (if term
	  (make-token :image (normalize self term)
		      :start start
		      :end end)
	  nil))))

(defmethod token-regexp ((self regexp-tokenizer))
  (cl-ppcre:create-scanner "\\w+" :multi-line-mode T))

(defmethod normalize ((self regexp-tokenizer) str)
  str)

(defclass lower-case-tokenizer (tokenizer)
  ())

(defmethod normalize ((self lower-case-tokenizer) str)
  (string-downcase str))


(defclass whitespace-tokenizer (regexp-tokenizer)
  ())

(defmethod token-regexp ((self whitespace-tokenizer))
  (cl-ppcre:create-scanner "\\S+" :multi-line-mode T))
  
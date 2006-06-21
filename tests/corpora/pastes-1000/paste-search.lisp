;; Example code showing how to use Montezuma to index and search
;; Lisppastes.
;;
;; I grabbed 1000 pastes from <http://paste.lisp.org> and saved them
;; in pastes.sexp.
;;
;; Example usage:
;;
;;   CL-USER> (use-package '#:paste-search)
;;   T
;;   CL-USER> (index-pastes)
;;   Indexing 1000 pastes... Indexing took 55.638 seconds.
;;   Optimizing... Optimizing took 30.613 seconds.
;;   ; No value
;;   CL-USER> (search-pastes "public class")
;;   Score  Date                 #      User             Title
;;   -----  -------------------  -----  ---------------  -----
;;    1.36  2006-05-01 11:35:55  19570  davidhouse       my ssh public key
;;    1.22  2006-04-10 22:42:12  18846  RyanT5000        Skin class
;;    1.10  2006-04-25 17:54:59  19366  lnostdal         calling constructor of base class
;;    1.03  2006-04-21 15:55:12  19232  Cale             Fst and Snd class
;;    0.93  2006-05-08 20:47:41  19820  Zarutian         part of SEXPparser class
;;    0.93  2006-05-08 20:43:10  19819  Zarutian         part of SEXPparser class
;;    0.93  2006-05-04 16:07:26  19685  kombinator       no class functions
;;    0.41  2006-05-02 12:34:28  19619  b42              error: looser throw specifier for ...
;;    0.41  2006-05-02 12:14:46  19618  b42              error: looser throw specifier for ...
;;    0.35  2006-04-19 15:18:20  19156  vampire0         Test.java
;;   10 results in 0.088 seconds.
;;
;; See the search-posts function below for more query examples.

(cl:defpackage #:paste-search
  (:use #:common-lisp)
  (:export #:*pastes-path*
	   #:*index-path*
	   #:index-pastes
	   #:search-pastes))

(in-package #:paste-search)


;; -- Variables

(defparameter *pastes-path*
  (make-pathname :name "pastes"
		 :type "sexp"
		 :defaults *load-pathname*)
  "The directory containing the Lisppaste archives.")

(defvar *index-path*
  (merge-pathnames (make-pathname :directory '(:relative "pasteindex"))
		   (make-pathname :name nil
				  :type nil
				  :defaults *load-pathname*))
  "The path at which to store the index.")

(defvar *index* nil
  "The Montezuma index for the Lisppaste archives.")


;; -- Macros

(defmacro time-form (format form)
  `(multiple-value-bind (result time)
       (time-thunk #'(lambda () ,form))
     (format T ,format time)
     result))

(defun time-thunk (thunk)
  (let* ((start (get-internal-run-time))
	 (result (funcall thunk))
	 (end (get-internal-run-time)))
    (values result (/ (- end start) internal-time-units-per-second))))


;; -- Indexing

(defstruct paste
  number
  user
  date
  channel
  title
  contents
  annotations)


(defun index-pastes ()
  (let ((index (make-instance 'montezuma:index
			      :path *index-path*
			      :create-p T
			      ;; Setting :min-merge-docs to 5000 helps
			      ;; keep most of the indexing in RAM.
			      ;; You might want to decrease this if
			      ;; you're RAM-starved.
			      :min-merge-docs 5000))
	(pastes (with-open-file (in *pastes-path* :direction :input)
		  (cl:read in))))
      (format T "~&Indexing ~S pastes... " (length pastes))
      (time-form
       "Indexing took ~,3F seconds."
       (dolist (paste pastes)
	 (index-paste index paste)))
      (format T "~&Optimizing... ")
      (time-form "Optimizing took ~,3F seconds."
		 (montezuma:optimize index))
      (montezuma:close index)
      (values)))


(defun index-paste (index paste)
  ;; Each paste is a separate document.
  (let ((doc (make-instance 'montezuma:document)))
    ;; We want to be able to search on the ID field, but it should not
    ;; be tokenized.
    (montezuma:add-field doc (montezuma:make-field "id" (format nil "~S" (paste-number paste))
						   :index :untokenized))
    ;; The USER field is stored and tokenized.
    (montezuma:add-field doc (montezuma:make-field "user" (paste-user paste)
						   :index :tokenized))
    ;; Convert dates from universal times to strings like
    ;; "2006-06-06".  Because of the way Montezuma does DATE queries
    ;; (the secret is that they're no different from any other query),
    ;; there is some advantage in decreasing the number of unique
    ;; terms, so we limit the resolution to one day.
    (montezuma:add-field doc (montezuma:make-field "date" (date-string (paste-date paste))
						   :index :untokenized :stored NIL))
    ;; The DATEDISPLAY field is not meant to be queried, it exists only to
    ;; show search results with timestamps of a nice 1 second resolution, like
    ;; "2006-06-06 23:59:59".
    (montezuma:add-field doc (montezuma:make-field "displaydate" (timestamp-string (paste-date paste))
						   :index :untokenized))
    ;; Store and tokenize the CHANNEL, TITLE and CONTENTS fields.
    (montezuma:add-field doc (montezuma:make-field "channel" (paste-channel paste)
						   :index :tokenized))
    (montezuma:add-field doc (montezuma:make-field "title" (paste-title paste)
						   :index :tokenized))
    (montezuma:add-field doc (montezuma:make-field "contents" (paste-contents paste)
						   :index :tokenized))
    ;; Finally, add the document to the index.
    (montezuma:add-document-to-index index doc)))


;; -- Searching

(defun load-index ()
  (setf *index* (make-instance 'montezuma:index
			       :path *index-path*
			       :create-p NIL
			       :create-if-missing-p NIL
			       ;; Unless otherwise specified, queries
			       ;; will search all these fields
			       ;; simultaneously.
			       :default-field "*"
			       :fields '("user" "channel" "title" "contents"))))


;; Example searches:
;;
;; (search-pastes "public class")
;; (search-pastes "+user:lemonodor +date:2006-04*")
;; (search-pastes "user:lemonodor" '(:num-docs 10000) T)
;; (search-pastes "bug*" '(:num-docs 10))
;; (search-pastes "bug*" '(:num-docs 10 :first-doc 10))
;; (search-pastes "date:2006-05*" '(:num-docs 10000) T)

(defun search-pastes (query &optional options count-only-p)
  "Searches the paste index."
  (unless *index*
    (load-index))
  (let ((results '()))
    (multiple-value-bind (value time)
	(time-thunk #'(lambda ()
			(montezuma:search-each *index* query
					       #'(lambda (doc score)
						   (push (cons doc score) results))
					       options)))
      (declare (ignore value))
      (unless count-only-p
	(format T "~&~5A  ~19A  ~5A  ~15A  ~A" "Score" "Date" "#" "User" "Title")
	(format T "~&-----  -------------------  -----  ---------------  -----")
	(dolist (result (reverse results))
	  (print-result (car result) (cdr result))))
      (format T "~&~S results in ~,3F seconds." (length results) time))))


(defun print-result (doc score)
  (let ((paste (montezuma:get-document *index* doc)))
    (flet ((get-field (name)
	     (montezuma:field-data (montezuma:document-field paste name))))
    (format T "~&~5,2F  ~A  ~A  ~15A ~vt~A"
	    score
	    (get-field "displaydate")
	    (get-field "id")
	    (get-field "user")
	    10
	    (get-field "title")))))


;; -- Misc.

(defun date-string (universal-time)
  "Turns a universal time into a string like \"2006-06-06\"."
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time universal-time)
    (declare (ignore second minute hour))
    (format nil "~D-~2,'0D-~2,'0D" year month date)))


(defun timestamp-string (universal-time)
  "Turns a universal time into a string like \"2006-06-06 23:59:59\"."
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time universal-time)
    (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
	    year month date hour minute second)))

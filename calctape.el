;;; calctape.el --- Adding-machine, tape calculator, column sum-mer -*- lexical-binding:t -*-

;; Copyright ©2025 Boruch Baum <boruch_baum@gmx.com>

;; Author: Boruch Baum <boruch_baum@gmx.com>
;; Homepage: https://github.com/Boruch-Baum/emacs-calctape
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: convenience, data
;; Package: calctape
;; Version: 1.0
;; Package-Requires: ((emacs "29.1"))

;; This file is NOT part of GNU Emacs.

;; This is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your
;; option) any later version.

;; This software is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
;; Public License for more details.

;; You should have received a copy of the GNU General Public License along
;; with this software. If not, see <https://www.gnu.org/licenses/>.

;;
;;; Commentary:

;; At the time of this writing, the closest thing that Emacs had to
;; adding machine functionality is the `calc' "trail" window (see
;; variable `calc-display-trail'), with all its oddities, benefits,
;; and drawbacks. Other methods required either: 1) selecting a
;; rectangle of numbers and sending it to 'calc' for that package to
;; use internally in its own dedicated buffer; 2) transforming a
;; rectangle of numbers (and possibly their annotations) into an
;; 'org-mode' table and having that package handle it.
;;
;; This package provides an easy-to-use tape calculator functionality
;; natively and intuitively IN ANY BUFFER. You can use it to sum an
;; existing column of numbers, without even having to select the
;; entire region, and even if the numbers are badly aligned. You can
;; use it to create a "tape" in any writable buffer, include
;; annotations for each line, and "live-edit" a pre-existing tape. The
;; package auto-aligns its tapes, supports memory operations, performs
;; VAT / sales tax calculations, and seamlessly handles integers,
;; floats, and scientific notation on the same tape.
;;
;; As a sneaky bonus, a wrapper function to Emacs `quick-calc' is
;; provided for outputting numbers with thousands delimiters.

;;
;;; Dependencies (already part of Emacs):
;;
;; calc -- For `calc-eval', to avoid floating-point rounding errors
;;         eg. 1.0 + 1.0 = 1.999999999999
;;         `calc-eval' requires numbers be represented as strings.
;;         Example: (calc-eval "(4.10 + 4.30)")


;;
;;; Operation:
;;
;; This pacakge provides five interactive functions (and doesn't
;; require any major or minor modes!). It also includes one secret
;; bonus function for users of Emacs `quick-calc'.
;;
;; Use M-x `calctape-sum' to operate on a pre-existing column of raw
;; numbers that are not formatted as a tape. Just place POINT anywhere
;; in or near the column and let 'er rip. I'm using the term "column"
;; loosely in this context. The function should operate even if the
;; column is very badly aligned. The result should be a formatted tape
;; in-situ.
;;
;; Use M-x `calctape-create' to create a tape from scratch. Place
;; POINT wherever you want the tape to display, and run the command.
;; For each line of the tape, you will be prompted for a value and a
;; description. Pressing ENTER for a value will end the tape. For all
;; the details, and for the mathematical and memory operations
;; supported, see the function's docstring.
;;
;; Use M-x `calctape-delete' to remove one or more lines from an
;; existing tape and auto-update the tape. To delete a single line,
;; place POINT on that line before running the command. To delete N
;; lines from POINT, either specify a PREFIX-ARG or select a REGION
;; that includes part of those lines.
;;
;; Use M-x `calctape-edit' to edit the tape at POINT. The function will
;; prompt you for data to insert into the tape prior to the line at
;; POINT and update the entire tape after each line of insertion. Note
;; that for this function, the prompt will indicate the current sum at
;; POINT.
;;
;; Use M-x `calctape-strip-box' to remove from the tape around POINT
;; the unicode line-drawing characters that by default frame a tape.
;; You can change that default behaviour by toggling the BOOLEAN
;; customization variable `calctape-box' and you can modify the
;; characters used by altering customization variable
;; `calctape-box-chars'.
;;
;; Users of Emacs `quick-calc' can use interactive wrapper function
;; `calctape-qc' to perform `quick-calc' operations and get the output
;; formatted with thousands delimiters.


;;
;;; Configuration
;;
;; See M-x `customize-group' `calctape'.

;;
;;; Feedback:
;;
;; It's best to contact me by opening an "issue" on the package's
;; github repository (see above) or, distant second-best, by direct
;; e-mail.
;;
;; Code contributions are welcome and github starring is appreciated.
;;

;;
;;; Compatibility
;;
;; This package has been tested under debian linux Emacs version 30.
;; My guess is that it ought to work on ancient Emacsen; if you try
;; it, please let me know.

;;
;;; TODOs
;;
;; TODO: Currency signs?
;; TODO: Numbers in parentheses as negative numbers?
;; TODO: Different bases (binary, octal, hexadecimal)?
;; TODO: Rounding and significant digits?
;; TODO: Force sums to scientific notation?
;;       eg. (format "%.6e" (string-to-number (calc-eval "2^50")))
;; TODO: Undo last action?


;;
;;; Code:

;;
;;; Dependencies
(require 'calc)  ; For `calc-eval'


;;
;;; Constants:

(defconst calctape--operator-regex "\\(\\([-+\\*/=T]\\)\\|\\(%[-+/\\*]?\\)\\)?"
  "Mathematical operators meant to be input post-fix valid number values.
In addition to \='+\=', \='-\=', \='*\=', \='/\=', there several percentage operators
that operate on the current sub-total SUM: \='%\=' or \='%+\=' adds a percentage
of SUM to SUM, \='%-\=' subtracts a percentage of SUM from SUM, and \='%*\='
multiplies SUM by a percentage. The tax operator \='T\=' is equivalent to
performing \='%+\=' using the value stored in configuration variable
`calctape-tax-rate'.")

(defconst calctape--controls-regex  "\\([cC]\\)\\|\\([mM][cC]\\)\\|\\([mM][-+*/]?\\)\\|\\([mM][rR][-+]?\\)\\|\\([mM][sS]\\)\\|\\([tT]\\)"
  "Control operation strings available in lieu of valid number values.
None are case-sensitive.

  C   :: clears total only (not memory) and begins a new tape
  MC  :: clears memory only (not total)
  M   :: adds current total to memory
  M+  :: adds current total to memory
  M-  :: subtracts current total from memory
  MR  :: adds memory to current total
  MR+ :: adds memory to current total
  MR- :: subtracts memory from current total
  MS  :: swaps total with memory
  T   :: (+ (* (car `calctape-tax-rate') sum) sum)")

(defconst calctape--clear-op-description "SUM CLEARED (MEMORY RETAINED)"
  "Message indication \"Clear\" operation performed.")


;;
;;; Variables:

(defvar calctape--value-history (list "")
  "History of values entered into tapes.")

(defvar calctape--description-history (list "")
  "History of descriptions entered into tapes.")



;;
;;; Customization variables:

(defgroup calctape nil
  "Adding-machine, tape calculator, column-sum-mer."
  :prefix "calctape"
  :group 'tools
  :group 'applications)

(defcustom calctape-op-dist 3
  "Spacing between an operator sign and a number."
  :type 'integer
  :set (lambda (sym val)
         (if (and (integerp val) (> val 0))
             (set-default sym val)
           (error "Value must be a positive integer"))))

(defcustom calctape-desc-dist 3
  "Spacing between a number and a description string."
  :type 'integer
  :set (lambda (sym val)
         (if (and (integerp val) (> val 0))
             (set-default sym val)
           (error "Value must be a positive integer"))))

(defcustom calctape-tax-rate (cons "0.08875" "New York City sales tax")
  "Data for tax operations."
;; TODO: Find a major location with a more obnoxious tax-rate than New
;; York City's sales tax.
  :type '(cons (string :tag "Tax rate, as a decimal fraction, not as a percentage")
               (string :tag "Description"))
  :set (lambda (sym val)
         (if (and (stringp (car val))
                  (calc-eval (format "1 > %s > 0" (car val)) 'pred))
             (set-default sym val)
           (error "Value must be a positive decimal fraction"))))

(defcustom calctape-position-sanity-distance 20
  "Maximum distance from POINT to create a tape.
This variable supports an experimental and limited feature of
`calctape'. If `calctape' detects that POINT is at a position in a
buffer that makes no sense for a tape, it may create the tape nearby
instead. This variable's value is how far away from POINT `calctape'
will check for a suitable place. See function
`calctape--position-sanity-check'."
  :type 'integer
  :set (lambda (sym val)
         (if (and (integerp val) (> val 0))
             (set-default sym val)
           (error "Value must be a positive integer"))))

(defcustom calctape-box t
  "Attempt to use Unicode characters to draw an box around a tape.
This is an experimental feature."
  :type 'boolean)

(defcustom calctape-perform-realignment t
  "Attempt to align mis-aligned numbers and comments.
This feature option is only available for use with function
`calctape-sum'. Setting this variable to NIL is not recommended."
  :type 'boolean)

(defcustom calctape-box-chars '("│" "─" "┌" "┐" "└" "┘")
  "Unicode characters used to draw boxes around tapes.

Some character sets that might interest you include:

BOX DRAWINGS LIGHT: `(\"│\" \"─\" \"┌\" \"┐\" \"└\" \"┘\")
BOX DRAWINGS HEAVY: `(\"┃\" \"━\" \"┏\" \"┓\" \"┗\" \"┛\" )

For other line styles, browse the Unicode database (eg. BOX DRAWINGS
LIGHT DOUBLE DASH, BOX DRAWINGS LIGHT TRIPLE DASH, BOX DRAWINGS LIGHT
QUADRUPLE DASH,).

Other corner styles are also available (eg. BOX DRAWINGS LIGHT ARC, BOX
DRAWINGS LIGHT DIAGONAL)."
  :type '(list (string :tag "Vertical")
               (string :tag "Horizontal")
               (string :tag "Upper left corner")
               (string :tag "Upper right corner")
               (string :tag "Lower left corner")
               (string :tag "Lower right corner"))
  :set (lambda (sym val)
         (let ((x 0))
           (while (< x 6)
             (when (/= 1 (length (nth x val)))
               (error "Value must be a single charcaters (%s)" x))
             (cl-incf x))
           (set-default sym val))))

(defcustom calctape-strip-box-carefully nil
  "Algorithm to use for removing box characters.
Setting this variable NON-NIL is useful if you have multiple tapes
side-by-side, or or a tape side-by-side other `calctape-box-chars'. See
customization variable `calctape-box-chars' and internal functions
`calctape--strip-box', `calctape--strip-box-careful', and
`calctape--strip-box--sloppy'."
  :type 'boolean)

(defcustom calctape-total-line-char "="
  "Character to use to draw total lines."
  :type 'string
  :set (lambda (sym val)
         (if (/= 1 (length val))
           (error "Value must be a single character")
          (set-default sym val))))

(defun calctape--validate-symbols (_sym _val) "" t) ; real defun below
;; NOTE: Using `declare-function' (as below) causes `load-file' of this package to
;; fail, although `eval-buffer' does work.
;; (declare-function calctape--validate-symbols nil (_sym _val)) ; real defun below
(defcustom calctape-symbols (cons "." ",")
  "Symbols to use for decimal points and thousands delimiters."
  :type '(cons (string :tag "Decimal point character")
               (string :tag "Thousands delimiter character"))
  :set (lambda (sym val)
         (and (calctape--validate-symbols sym val)
            (set-default sym val))))

(defgroup calctape-description nil
  "Default description format strings for tape operations."
  :group 'calctape
  :prefix "calctape-description-")

(defcustom calctape-description-mem-clear "MEMORY CLEARED"
  "Default description format for \"memory clear\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-plus "ADDED %s TO MEMORY"
  "Default description format for \"memory plus\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-minus "SUBTRACTED %s FROM MEMORY"
  "Default description format for \"memory minus\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-times "MULTIPLIED MEMORY by %s"
  "Default description format for \"memory multiply\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-divide "DIVIDED MEMORY BY %s"
  "Default description format for \"memory divide\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-current "CURRENT MEMORY VALUE"
  "Default description format for \"memory recall\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-mem-swap "SWAP %s WITH MEMORY"
  "Default description format for \"memory swap\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-tax "TAX ON %s (%4$s%%)"
  "Default description format for \"tax\" operations.
See docstring for function `calctape--desc-fmt'."
  :type 'string)

(defcustom calctape-description-percent  "%2$s PERCENT OF %1$s"
  "Default description format for \"percent\" operations.
See docstring for function `calctape--desc-fmt'."
:type 'string)



;;
;;; Macros:


(defmacro calctape--desc-fmt (fmt)
  "Produce a default description.
FMT should be one of the format strings defined in the
`calctape-description' customization group. Those format strings may
refer to internal `calctape' string variables. The available variables
are for the tape's current sum, the current value being entered, the
current value of memory, and the current tax rate. If a format string
refers to those internal variable in that sequence, it is sufficient to
refer to them within the format string as \"%s\". Otherwise. it is
necessary to use the notation \"%N$s\".

  %1$s current sum (sub-total)
  %2$s current value entered by user
  %3$s current memory (register)
  %4$s current tax rate"
  `(format ,fmt thou-sum thou-value thou-mem thou-tax))


;;
;;; Internal functions:

(defun calctape--validate-symbols (_sym val)
  "Validate decimal point and thousands delimiter symbols.
SYM and VAL are as produced by `defcustom' `calctape-symbols'. Returns
SYM (a CONS of the decimal point and thousands delimiter strings) upon
success."
  (when (string= (car val) (cdr val))
    (error "Decimal point and thousands delimiter character must be different"))
  (when (/= 1 (length (car val)))
    (error "Decimal point symbol must be a single character"))
  (when (/= 1 (length (cdr val)))
    (error "Thousands delimiter symbol must be a single character"))
  val)

(defun calctape--full-num-regex-SLACK ()
  "Return a full number REGEX with thousands delimiters.
This REGEX string has three sub-groups:
   1: Signed integer
   2: Decimal point and value
   3: Scientific notation

IMPORTANT: This version of the regex has sloppily included support for
number strings containing thousands delimiters. Expect false positives!"
  (when (calctape--validate-symbols nil calctape-symbols)
    (concat "\\([+-]?[[:digit:]][[:digit:]"
            (cdr calctape-symbols) ; thousands delimiter
            "]*\\)\\(["
            (car calctape-symbols) ; decimal point
            "][[:digit:]]*\\)?\\([eE]\\([+-]?[[:digit:]]+\\)\\)?")))


(defun calctape--full-num-regex ()
  "Return a full number REGEX with thousands delimiters.
This REGEX string has three sub-groups:
   1: Signed integer
   2: Decimal point and value
   3: Scientific notation"
  (when (calctape--validate-symbols nil calctape-symbols)
    (concat "\\([+-]?[[:digit:]]+\\)\\(["
            (car calctape-symbols) ; decimal point
            "][[:digit:]]*\\)?\\([eE]\\([+-]?[[:digit:]]+\\)\\)?")))


(defun calctape--line-regex ()
  "Return a REGEX for a full line of a tape.
This REGEX string has ten sub-groups:
   1,2: Operator
   4:   Whitespace
   5:   Full-number
   6:   Signed integer
   7:   Decimal
   8:   Full-exponent
   9:   Signed exponent integer
  10:   Whitespace

This variable is used by function `calctape--tabulate'."
  (concat calctape--operator-regex
          "\\([[:blank:]]+\\)"
          "\\("
          (calctape--full-num-regex-SLACK)
          "\\)"
          "\\([[:blank:]]+\\)?"))


(defun calctape--match-thous (num)
  "Validate NUM is a series of three digits.
Returns NUM on success, and raises and error on failure."
  (when (not (string-match "^[[:digit:]]\\{3\\}$" num))
    (error "calctape--match-thous: %s" num))
  num)

(defun calctape--delimit-num-check (num)
 "Validate NUM as a number with thousands delimiters.
Returns a number string without those delimiters."
;; TESTS:
;;   (calctape--delimit-num-check "-1.2e-3")
;;   (calctape--delimit-num-check "1,123")
;;   (calctape--delimit-num-check "-12,345,678.876e-13")
;;   (calctape--delimit-num-check "1")
;;   (calctape--delimit-num-check "1,1")
;;   (calctape--delimit-num-check "1,10f")
  (save-match-data
  (let ((err-msg "calctape--delimit-num-check: %s failure (%s): %s")
        (split-regex (concat "^\\([^"
                             (car calctape-symbols) ; decimal point
                             "e]+\\)?\\(["
                             (car calctape-symbols) ; decimal point
                             "][^e]+\\)?\\(e.*\\)?$"))
        (signed-regex  "^[+-]?\\([[:digit:]]+\\)$")
        (dec-regex  (concat "^["
                             (car calctape-symbols) ; decimal point
                            "][[:digit:]]+$"))
        (exp-regex "^[eE][+-]?[[:digit:]]+$")
        int dec exp split extra)
   (unless (string-match split-regex num)
      (error err-msg "regex" "split" num))
   (setq int (match-string 1 num))
   (setq dec (match-string 2 num))
   (setq exp (match-string 3 num))
   (when int
     (setq split (split-string
                   int
                   (cdr calctape-symbols))) ; thousands delimiter
     (setq extra (pop split))
     (unless (string-match signed-regex extra)
       (error err-msg "regex" "int 1" extra))
     (unless (> 4 (length (match-string 1 extra)))
       (error err-msg "length" "int 1" extra))
     (setq int
       (concat extra
               (mapconcat #'calctape--match-thous split))))
   (when dec
     (unless (string-match dec-regex dec)
       (error err-msg "regex" "dec" dec)))
   (when exp
     (unless (string-match exp-regex extra)
       (error err-msg "regex" "exp" exp)))
   (concat int dec exp))))


(defun calctape--delimit-num (num)
  "Add thousands delimiters to number string NUM.
NUM must match regex `calctape--full-num-regex'."
;; TESTS:
;;   (calctape--delimit-num "-1.2e-3")
;;   (calctape--delimit-num "1123")
;;   (calctape--delimit-num "123456")
;;   (calctape--delimit-num "-12345678.8765")
;;   (calctape--delimit-num "11,23")
  (let ((err-msg "calctape--delimit-num: %s failure (%s): %s")
        (num-regex (concat "^" (calctape--full-num-regex) "$"))
        (signed-regex  "^\\([+-]\\)?\\([[:digit:]]+\\)$")
        (extra-regex "\\([[:digit:]]\\{%s\\}\\)")
        (thous-regex "\\([[:digit:]]\\{3\\}\\)")
        -regex
        int dec exp int-sign len groups extra)
    (unless (string-match num-regex num)
      (error err-msg "regex" "full-num" num))
    (setq int (match-string 1 num))
    (setq dec (match-string 2 num))
    (setq exp (match-string 3 num))
    (when int
      (unless (string-match signed-regex int)
        (error err-msg "regex" "int" int))
      (when (< 3 (setq len (length (match-string 2 int))))
        (when (setq int-sign (match-string 1 int))
          (setq int (substring int 1)))
        (setq groups (/ len 3))
        (setq extra  (mod len 3))
        (setq -regex
          (concat (unless (zerop extra)
                    (format extra-regex extra))
                  (mapconcat (lambda (_x) thous-regex)
                             (number-sequence 1 groups)
                             "")))
        (when (string-match -regex int)
          (setq int
            (concat int-sign
                    (mapconcat (lambda (x) (match-string x int))
                               (number-sequence 1 (1+ groups))
                               (cdr calctape-symbols)))))
        (when (string= (cdr calctape-symbols)
                       (substring int -1))
          (setq int (substring int 0 -1)))))
    (concat int dec exp)))

(defun calctape--position-sanity-check ()
  "Deal with attempts to create a tape in an undesirable position."
  (let ((error-msg "calctape-create: POINT is not in an empty area of the buffer. (#%s)")
        (start-pos (point))
        blank-len)
    (cond
     ((eolp)
       (when (not (bolp))
          (when (and (re-search-backward "[^[:blank:]]" (line-beginning-position) t)
                     (> calctape-desc-dist (- start-pos (match-end 0))))
            (goto-char start-pos)
            (insert-char #x20 calctape-desc-dist))))
     ((looking-at "[^[:blank:]]")
       (cond
        ((re-search-forward "\\([^[:blank:]]+\\)\\([[:blank:]]+\\)?$" (line-end-position) t)
          (when (< calctape-position-sanity-distance
                  (length (match-string 1)))
            (goto-char start-pos)
            (user-error error-msg "1"))
          (if (< calctape-desc-dist
                (setq blank-len (length (or (match-string 2) ""))))
            (goto-char (+ (match-beginning 2) calctape-desc-dist))
           (end-of-line)
           (insert-char #x20 (- calctape-desc-dist blank-len))))
        (t (user-error error-msg "2")))))
    (goto-char start-pos)))


(defun calctape--strip-box (&optional pos)
  "Remove the box surrounding the tape at POS or POINT.
This is a wrapper function that calls either
`calctape--strip-box--sloppy' or `calctape--strip-box-careful'. See also
customization variable `calctape-strip-box-carefully'."
  (let ((start-point (point))
        (undo-list buffer-undo-list))
    (or (unless calctape-strip-box-carefully
          (condition-case err
            (calctape--strip-box--sloppy pos)
            (error ; handler for `condition-case'
              (primitive-undo (- (length buffer-undo-list)
                                 (length undo-list))
                              buffer-undo-list)
              (message "%s" (substring err 12 -2)))))
        (condition-case err
          (progn
            (goto-char start-point)
            (setq undo-list buffer-undo-list)
            (calctape--strip-box--careful pos))
          (error ; handler for `condition-case'
            (primitive-undo (- (length buffer-undo-list)
                               (length undo-list))
                            buffer-undo-list)
            (message "%s" (substring err 12 -2)))))))


(defun calctape--strip-box--sloppy (&optional pos)
  "Remove the box surrounding the tape at POS or POINT.
This function quickly removes elements of `calctape-box-chars' in a
simple way that always otherwise preserves buffer contents. However, it
can fail either when a second tape is anywhere beside the intended tape,
or when the buffer has stray box characters near the intended tape. If
you are concerned with those cases, set customization variable
`calctape-strip-box-carefully' to NON-NIL."
;; TODO: Delete this function and always use `calctape--strip-box--careful'?
  (let ((pos (or pos (point)))
        begin-pos
        end-mark)
    (goto-char pos)
    (unless (search-backward (nth 2 calctape-box-chars) nil t) ; "┌"
      (error "calctape--strip-box: Upper-left corner not found"))
    (setq begin-pos (point))
    (replace-match " ")
    (unless (search-forward (nth 5 calctape-box-chars) nil t) ; "┘"
      (error "calctape--strip-box: Lower-right corner not found"))
    (setq end-mark (point-marker))
    (replace-match " ")
    (mapc
      (lambda (x)
        (goto-char begin-pos)
        (while (search-forward x end-mark t)
          (replace-match " ")))
      (list (nth 0 calctape-box-chars)
            (nth 1 calctape-box-chars)
            (nth 3 calctape-box-chars)
            (nth 4 calctape-box-chars)))))


(defun calctape--strip-box--careful (&optional pos)
  "Remove the box surrounding the tape at POS or POINT."
  (when pos (goto-char pos))
  (let* ((-vert (car calctape-box-chars))
         (-vert-right (concat " " -vert))
         (-vert-left (concat -vert " "))
         (-horz (cadr calctape-box-chars))
         (-corn (cddr calctape-box-chars))
         temp-marker)
    (unless (search-forward -vert-right (line-end-position) t)
      (user-error "calctape-strip-box: Right vertical char not found.?"))
    (backward-char 2)
    (setq temp-marker (point-marker))
    (while (looking-at -vert-right)
      (replace-match "")
      (rectangle-next-line 1))
    (forward-char 1)
    (unless (looking-at (nth 3 -corn)) ; lower right corner
      (user-error "calctape-strip-box: Char not found (%s).?" (nth 3 -corn)))
    (replace-match "")
    (unless (re-search-backward (concat (nth 2 -corn) -horz "+")
                                (line-beginning-position) t)
      (user-error "calctape-strip-box: Bottom line not found.?"))
    (replace-match (string-pad "" (- (length (match-string 0)) 3) #x20))
    ;; in the above `replace-match', minus 3 corresponds to concat -vert and space
    (goto-char (match-beginning 0))
    (rectangle-previous-line 1)
    (unless (looking-at -vert-left)
      (user-error "calctape-strip-box: Left vertical char not found.?"))
    (while (looking-at -vert-left)
      (replace-match "")
      (rectangle-previous-line 1))
    (unless (looking-at (nth 0 -corn))
      (user-error "calctape-strip-box: Char not found (%s).?" (nth 0 -corn)))
    (replace-match "")
    (unless (looking-at (concat -horz "+" (nth 1 -corn)))
      (user-error "calctape-strip-box: Top line not found.?"))
    (replace-match (string-pad "" (- (length (match-string 0)) 3) #x20))
    ;; in the above `replace-match', minus 3 corresponds to concat -vert and space
    (goto-char temp-marker)
    (rectangle-previous-line 1)
    (while (looking-at -vert-right)  ;; ??
      (replace-match "")
      (rectangle-previous-line 1))))


(defun calctape--make-box (upper-left-pos lower-left-pos rightmost-column)
  "Draw a box around a tape.

UPPER-LEFT-POS and LOWER-LEFT-POS are buffer positions. RIGHTMOST-COLUMN
is a column number. CALLED-BY-EDIT indicates whether called indirectly
from interactive function `calctape-create' or `calctape-edit'."
  (let ((-vert (car calctape-box-chars))
        (-horz (cadr calctape-box-chars))
        (-corn (cddr calctape-box-chars))
        leftmost-column
        line-end-column
        line-width
        start-point-marker ; where to return when finished
        first-line-of-tape
        last-line-of-tape
        vert-lines-to-do
        horz-line
        (back-col 2)         ; check whether left vert line ...
        (back-col-str "  ")  ; ... should be before `leftmost-column'
        (upper-left-marker (make-marker)))
    (setq start-point-marker (point-marker))
    (set-marker upper-left-marker upper-left-pos)
    (set-marker-insertion-type upper-left-marker t)
    (goto-char upper-left-pos)
    (setq leftmost-column (current-column))
    (cl-incf rightmost-column 4) ; explain '4'
    (setq first-line-of-tape (line-number-at-pos))
    (setq last-line-of-tape (+ 2 (line-number-at-pos lower-left-pos))) ; '2' for border lines
    (setq line-width  (- rightmost-column leftmost-column -2)) ; '2' for corner chars
    (setq vert-lines-to-do (- last-line-of-tape first-line-of-tape))
    (when (= 1 (line-number-at-pos))
      (cl-incf last-line-of-tape)
      (forward-line 0)
      (insert "\n"))
    (when (not (zerop leftmost-column))
      (forward-line -1)
      (when (= 1 leftmost-column)
        (setq back-col 1)
        (setq back-col-str " "))
      (while (and (< 0 (cl-decf vert-lines-to-do))
                  (not (zerop back-col)))
        (forward-line 1)
        (forward-char (- leftmost-column back-col))
        (unless (looking-at back-col-str)
          (cl-decf back-col)
          (setq back-col-str " ")
          (when (not (zerop back-col))
            (forward-char)
            (unless (looking-at back-col-str)
            (cl-decf back-col)))))
      (when (not (zerop back-col))
        (setq vert-lines-to-do (- last-line-of-tape first-line-of-tape))
        (goto-char upper-left-pos)
        (forward-line -1)
        (while (< 0 (cl-decf vert-lines-to-do))
          (forward-line 1)
          (forward-char (- leftmost-column back-col))
          (delete-char back-col)))
      (setq rightmost-column (- rightmost-column back-col))
      (setq vert-lines-to-do (- last-line-of-tape first-line-of-tape))
      (setq leftmost-column (- leftmost-column back-col)))
    (goto-char upper-left-pos)
    ;; top box line
    (forward-line -1)
    (setq line-end-column (progn (end-of-line)
                                 (current-column)))
    (forward-line 0)
    (cond
     ((< line-end-column leftmost-column)
       (end-of-line)
       (insert-char #x20 (- leftmost-column line-end-column)))
     (t ; top box line may have non-blank characters where we want to box
       (forward-char leftmost-column)
       ;; When line above might not be available for overwrite
       (re-search-forward "\\([[:blank:]]+\\)?\\([^[:blank:]]\\)?"
                          (min (+ (point) line-width 2) (line-end-position))
                          t)
       (goto-char (+ (line-beginning-position) leftmost-column))
       (cond
        ((match-beginning 2) ; There is a non-blank char on the line
          (if (>= (- (match-beginning 2) (point)) line-width)
            (delete-char (- line-width)) ; It is to right of table
           (end-of-line)
           (insert "\n")
           (insert-char #x20 leftmost-column)))
        ((match-beginning 1)
          (delete-region (point) (min (+ (point) line-width) (line-end-position)))))))
    (setq horz-line (string-pad "" (- line-width 2) (string-to-char -horz)))
    (insert (format "%s%s%s" (nth 0 -corn) horz-line (nth 1 -corn)))
    ;; tape body
    (while (< 0 (cl-decf vert-lines-to-do))
      (forward-line)
      (forward-char leftmost-column)
      (insert (format "%s " -vert))
      (setq line-end-column (progn (end-of-line)
                                   (current-column)))
      (cond
       ((< line-end-column rightmost-column)
        (end-of-line)
        (insert-char #x20 (- rightmost-column line-end-column)))
       (t
        (beginning-of-line)
        (forward-char rightmost-column)
        (when (looking-at "  ")
          (delete-char 2))))
      (insert (format " %s" -vert)))
    ;; bottom line
    (cond
     ((eobp)
       (insert "\n")
       (insert-char #x20 leftmost-column))
     ((= (line-number-at-pos) (line-number-at-pos (point-max)))
       (goto-char (point-max))
       (insert "\n")
       (insert-char #x20 leftmost-column))
     (t
      (forward-line)
      (setq line-end-column (progn (end-of-line)
                                   (current-column)))
      (cond
       ((< line-end-column leftmost-column)
        (end-of-line)
        (insert-char #x20 (- leftmost-column line-end-column)))
       (t
        (beginning-of-line)
        (forward-char leftmost-column)
        (if (not (re-search-forward
                   "[^[:blank:]]"
                   (min (+ (point) line-width) (line-end-position))
                   t))
          (delete-char (min line-width (- (line-end-position) (point))))
         (beginning-of-line)
         (insert-char #x20 leftmost-column)
         (insert "\n")
         (backward-char 1))))))
    (insert (format "%s%s%s" (nth 2 -corn) horz-line (nth 3 -corn)))
    (goto-char start-point-marker)))


(defun calctape--get-description-len ()
  "Returns the length of the current tape line's description string."
  (goto-char (match-end 0))
  (if (re-search-forward "\\([^[:blank:]]+[[:blank:]]?\\)+"
                         (line-end-position) t)
    (length (match-string 0))
   0))


;; FIXME: This function seems unused and unnecessary
(defun calctape--look-back-from-decimal (line-begin-pos)
  "Validate number with decimal point.
This may be too strict. It requires numbers in an unformed list have
digits before decimal points.

LINE-BEGIN-POS is the `line-beginning-position'."
  (when (looking-at (concat "[" (car calctape-symbols) "]"))
    (when (/= (point) line-begin-pos)
      (backward-char))
    (when (not (looking-at "[[:digit:]]"))
      (user-error "Decimal point must be preceded by an integer"))
    (unless (re-search-backward "[^[:digit:]]" line-begin-pos t)
     (goto-char line-begin-pos))))


(defun calctape--look-at-number-prefix ()
  "Validate the character before a number's first digit.
It should be either whitespace or a +/- sign."
  (when (looking-at "[^[:blank:]+-]")
    (user-error "Bad number prefix.?")))


(defun calctape--find-number-string ()
   "Search for a number on the current line, near POINT.
If found, returns a list comprising of two versions of the number string
found (first in a format compatible with `calc-eval', then with
thousands delimiters), its beginning and ending column numbers on the
current line, and a guess as to the length of its description.

NOTE: This function will not find numbers with scientific notation if
they are behind `rectangle-previous-line'."
  (let ((start-col (current-column))
        search-resume-pos
        nearest-num-distance
        current-num
        current-num-thou
        current-num-begin-column
        current-num-len
        current-num-end-column
        current-num-distance
        description-len
        numbers-found) ; (list '(num-string begin-column end-column))
    (beginning-of-line)
    (while
      (and (re-search-forward (calctape--full-num-regex-SLACK)
                              (line-end-position)
                              t)
           (setq search-resume-pos (point))
           (setq current-num
             (setq current-num-thou
               (match-string-no-properties 0)))
           (save-match-data
             (or (condition-case _err
                   (setq current-num (calctape--delimit-num-check current-num))
                   (error nil))
                 (condition-case _err
                   (setq current-num-thou (calctape--delimit-num current-num))
                   (error nil)))))
      ;; only push if closer to start-col than previous number found on this line
      (setq current-num-begin-column (progn (goto-char (match-beginning 0)) (current-column)))
      (setq current-num-len (length current-num-thou))
      (setq current-num-end-column (+ current-num-begin-column current-num-len))
      (setq current-num-distance
        (if (< current-num-begin-column start-col current-num-end-column)
          0 ; current number spans start-col
         (min (abs (- start-col current-num-begin-column))
              (abs (- start-col current-num-end-column)))))
      (when (or (not nearest-num-distance)
                (>   nearest-num-distance current-num-distance))
        (setq nearest-num-distance current-num-distance)
        (replace-match current-num-thou)
        (setq search-resume-pos (point))
        (setq description-len (calctape--get-description-len))
        (push (list current-num
                    current-num-thou
                    current-num-begin-column
                    current-num-end-column
                    description-len)
              numbers-found))
      (goto-char search-resume-pos))
    (car numbers-found)))


(defun calctape--print-prep (min-col)
  "Ensure padding on left of operator symbol.

MIN-COL is the column to find a tape line's mathematical or control
operator symbol."
  (if (< (current-column) min-col)
    (insert-char #x20 (- min-col (current-column))))
   (backward-char (- (current-column) min-col)))


(defun calctape--advance-line (min-col)
  "Don't unnecessarily insert new lines into the current buffer.

MIN-COL is the column to find a tape line's mathematical or control
operator symbol."
  (cond
   ;; at end-of-buffer, rectangle-next-line doesn't create new line
   ((= (point) (progn (rectangle-next-line 1) (point)))
     (insert "\n"))
   ;; POINT is now amidst text instead of whitespace
   ((and (< (+ (line-beginning-position) min-col) (line-end-position))
         (string-match "[^[:blank:]]"
           (buffer-substring (+ (line-beginning-position) min-col)
                                (line-end-position))))
     (beginning-of-line)
     (insert "\n")
     (forward-line -1))))


(defun calctape--print-total-line (sum min-col max-int-len max-dec-len)
  "Prints a delimiter line and the tape total.
The delimiter line is based upon customization variable
`calctape-total-line-char'.

This function expects POINT to be at line under final row of numbers,
 which should always be the case at the conclusion of functions
 `calctape-sum' and `calctape-create'.

SUM is the tape's total.

MIN-COL is the column to find a tape line's mathematical or control
operator symbol.

MAX-INT-LEN is the length of the longest integer portion of a number in
the tape.

MAX-DEC-LEN is the length of the longest decimal portion of a number in
the tape, including the decimal point and any scientific notation."
  (let ((sum-string sum)
        sum-int-len)
    (string-match (calctape--full-num-regex-SLACK) sum-string)
    (setq sum-int-len (length (or (match-string 1 sum-string) "")))
    (when (> sum-int-len max-int-len)
      (setq min-col (max 0 (- min-col (- sum-int-len max-int-len)))))
    (calctape--print-prep min-col)
    (insert-char (string-to-char calctape-total-line-char)
                 (+ calctape-op-dist
                    (max max-int-len sum-int-len)
                    (max max-dec-len (+ (length (or (match-string 2 sum-string) ""))
                                        (length (or (match-string 3 sum-string) ""))))))
    (calctape--advance-line min-col)
    (calctape--print-prep min-col)
    (insert (format (format "=%%%ss%%s"
                            (+ calctape-op-dist (- max-int-len sum-int-len 1)))
                    "" sum-string))))


(defun calctape--print-total-for-clear (min-col max-len)
  "For user control operator \='C\=' (clear).

MIN-COL is the column to find a tape line's mathematical or control
operator symbol.

MAX-LEN is the length of the longest number in the tape."
  (calctape--print-prep  min-col)
  (insert-char (string-to-char calctape-total-line-char)
               (+ max-len calctape-op-dist))
  (insert-char #x20 calctape-desc-dist)
  (insert calctape--clear-op-description)
  (calctape--advance-line min-col)
  (calctape--advance-line min-col))

(defun calctape--perform-realignment (top-pos min-col max-len max-int-len
                                      &optional editing-sum-mark)
  "Realign a tape.

Expects POINT to be at line under final row of numbers. This should
always be the case when called by functions `calctape--create',
`calctape-edit', and `calctape-sum'.

TOP-POS is the upper-left position of the tape.

MIN-COL is the column to find a tape line's mathematical or control
operator symbol.

MAX-LEN is the length of the longest number in the tape.

MAX-INT-LEN is the length of the longest integer portion of a number in
the tape.

Optional argument EDITING-SUM-MARK is a buffer marker for the position
of the tape's total. It should be NON-NIL when this function is called
by functions `calctape--create' and calctape-sum'."
  ;; This next only properly handles comments AFTER the numbers
  (save-mark-and-excursion
    (let ((lines-to-do (- (1+ (line-number-at-pos (or editing-sum-mark
                                                      (point))))
                          (line-number-at-pos top-pos)))
          (max-dec-len (- max-len max-int-len)))
      (goto-char top-pos)
      (while (< 0 (cl-decf lines-to-do))
        (goto-char (+ min-col (line-beginning-position)))
        (when (looking-at (calctape--line-regex))
          (replace-match (string-pad " " (+ calctape-op-dist
                                            (- max-int-len
                                               (length (match-string 6))
                                               1)))
                         nil nil nil 4)
          (replace-match (string-pad " " (+ calctape-desc-dist
                                            (- max-dec-len
                                               (length (match-string 7)))))
                        nil nil nil 10)
          (forward-line))))))

(defun calctape--sum-update (num-data sum-struct)
  "Used by function `calctape-sum' to create an updated SUM-STRUCT.

Returns the new SUM-STRUCT.

NUM-DATA is a list consisting of
   number-string (`calc-eval' format)
   number-string (printable format, with thousands delimiters)
   start-col
   end-col
   desc-len

SUM-STRUCT is a list consisting of
  number-string (`calc-eval' format)
  number-string (printable format, with thousands delimiters)
  max-int-len    longest integer portion encountered
  max-dec-len    longest decimal portion encountered
  min-col        minimum column encountered
  max-col        maximum column encountered"
  (let* ((num (pop num-data))
         (num-thou (pop num-data))
         (sum (calc-eval (format "(%s + %s)"
                                 num
                                 (pop sum-struct))))
         (sum-thou (and (pop sum-struct)
                        (calctape--delimit-num sum)))
         (max-int-len (pop sum-struct))
         (max-dec-len (pop sum-struct))
         (sum-min-col (pop sum-struct))
         (sum-max-col (pop sum-struct))
         (min-col (if (not sum-min-col)
                     (pop num-data)
                    (min sum-min-col (pop num-data))))
         (max-col (if (not sum-max-col)
                     (1- (pop num-data))
                    (max sum-max-col (1- (pop num-data))))))
    (when calctape-perform-realignment
      (string-match (calctape--full-num-regex-SLACK) num-thou)
      (setq max-int-len (max max-int-len (or (length (match-string 1 num-thou)) 0)))
      (setq max-dec-len (max max-dec-len (or (length (match-string 2 num-thou)) 0))))
    (list sum sum-thou max-int-len max-dec-len min-col max-col)))


(defun calctape--operate (sum operator value)
  "Perform a math operation using function `calc-eval'.
SUM is the prior sum. OPERATOR and VALUE are the math operator and
operand to apply to the prior sum. Returns a new SUM.."
  (cond
   ((not operator)
    (calc-eval (format "(%s + %s)" sum value)))
   ((string= operator "-")
    (calc-eval (format "(%s - %s)" sum value)))
   ((string= operator "*")
    (calc-eval (format "(%s * %s)" sum value)))
   ((string= operator "/")
    (calc-eval (format "(%s / %s)" sum value)))
   ((string= operator "=")
    (calc-eval (format "(%s + %s)" sum value)))
   ((string= operator "T")
    (calc-eval (format "(%s + %s)" sum value)))
   (t
    (calc-eval (format "(%s + %s)" sum value)))))



(defun calctape--tabulate (sum
                           top-line
                           begin-column
                           max-len
                           max-int-len
                           editing-begin-mark)
"Dynamically update a tape during editing.

This function supports interactive function `calctape-edit' at two
points of operation. It is called directly, prior to prompting the user
for a first edit, in order to validate that POINT is within a valid
tape, obtain tape format details, and calculate the tape's total at
POINT and at its end. This function is later called indirectly from
`calctape-edit', via function `calctape--create' to update those tape
format details, tape total at POINT and tape total at end.

Function `calctape-edit' passes control to function
`calctape--create' (shared with interactive function `calctape-create')
for the actual prompting and insertions into the tape.

SUM is the tape total at POINT, ie. not the grand total at the tape's
end.

TOP-LINE is the buffer line number at the beginning of the tape.

BEGIN-COLUMN is the column to find a tape line's mathematical or control
operator symbol.

MAX-LEN is the length of the longest number in the tape.

MAX-INT-LEN is the length of the longest integer portion of a number in
the tape.

EDITING-BEGIN-MARK is a buffer marker, with insertion type NON-NIL, set
at the POINT insertions are being made into the tape. This value should
be nil when this function is called by `calctape--create'.

This function returns a list (needed only when called directly by
`calctape-edit') comprising of `editing-begin-sum', `max-len',
`max-int-len', and `max-desc-len'."
  (let ((invalid-tape-msg
           "calctape--tabulate: Not within a validly formatted tape (%s).")
        thou-value
        value
        operator
        editing-begin-sum
        (max-desc-len 0)
        (op-dist (string-pad "" calctape-op-dist #x20)))
    (forward-line 0)
    (forward-char begin-column)
    (while (looking-at (calctape--line-regex))
      (setq thou-value (match-string 5))
      (setq value (calctape--delimit-num-check thou-value))
      (setq max-len
        (max max-len (length value)))
      (setq max-int-len
        (max max-int-len (length (or (match-string 6) ""))))
      (setq operator (match-string 1))
      (when editing-begin-mark
        (when (< (point) editing-begin-mark)
          (setq editing-begin-sum sum))
        (setq max-desc-len
          (max max-desc-len (calctape--get-description-len))))
      (setq sum
        (cond
          ((string= operator "%+")
            (calc-eval (format "(%s + ((%s * %s) / 100) )" sum sum value)))
          ((string= operator "%-")
            (calc-eval (format "(%s - ((%s * %s) / 100) )" sum sum value)))
          ((string= operator "%*")
            (calc-eval (format "( (%s * %s) / 100)" sum value)))
          ((string= operator "T")
            (calc-eval (format "(%s + %s)" sum value)))
          (t
            (calc-eval (format "(%s %s %s)" sum operator value)))))
      (forward-line 1)
      (forward-char begin-column))
    (setq max-len (max max-len (length sum)))
    (setq max-int-len (max max-int-len
                           (or (string-match-p
                                 (concat "[eE" (car calctape-symbols) "]")
                                 sum)
                               (length sum))))
    ;; Validate delimiter line between tape values and total
    (unless (looking-at (concat calctape-total-line-char "+"))
      (user-error invalid-tape-msg (format "tape line %s"
                                           (- (line-number-at-pos)
                                              top-line
                                              -1))))
    ;; Update length of delimiter line
    (replace-match
      (string-pad ""
                  (+ max-len calctape-op-dist)
                  (string-to-char calctape-total-line-char)))
    ;; Validate line pre-existing total line
    (forward-line 1)
    (forward-char begin-column)
    (unless (looking-at (calctape--line-regex))
      (user-error invalid-tape-msg "total line"))
    ;; Update total line
    (replace-match (format (format "=%%%ss %%s" op-dist)
                           " "
                           sum))
    ;; return values as a list (needed only when called directly by `calctape-edit'
    (list editing-begin-sum max-len max-int-len max-desc-len)))


(defun calctape--delete (number-of-lines-to-delete
                         top-pos
                         begin-point
                         editing-begin-mark
                         begin-column
                         max-len
                         max-desc-len
                         editing-sum-mark
                         editing-begin-sum)
  "Delete lines from a tape."
  (let* ((line-width (+ calctape-op-dist
                        max-len ; (max max-len sum-len)
                        (if (zerop max-desc-len)
                          0
                         (+ calctape-desc-dist max-desc-len))))
         (end-column (+ line-width begin-column 2))
         begin-target
         begin-rect
         end-rect)
    (goto-char editing-begin-mark) ;begin-point)
    (setq begin-target (+ (line-beginning-position)
                      begin-column))
    (unless number-of-lines-to-delete
      (error "Calctape--delete: number-of-lines-to-delete is NIL"))
    (unless (< 0 (- (line-number-at-pos editing-sum-mark)
                    (line-number-at-pos)
                    number-of-lines-to-delete))
      (user-error
        "Calctape--delete: number-of-lines-to-delete exceeds size of tape.?"))
    (forward-line (1- number-of-lines-to-delete))
    (delete-rectangle begin-target
                      (min (line-end-position)
                           (+ (line-beginning-position)
                              end-column)))
    (forward-line 1)
    (setq begin-rect (+ (line-beginning-position)
                        begin-column))
    (goto-char editing-sum-mark)
    (end-of-line)
    (when (< (current-column) end-column)
      (insert-char #x20 (- end-column (current-column))))
    (setq end-rect (+ (line-beginning-position)
                      end-column))
    (kill-rectangle begin-rect end-rect 'fill)
    (goto-char begin-target)
    (yank-rectangle)
    (goto-char begin-target)
    (calctape--tabulate editing-begin-sum ; was: "0" ; initial sum
                        (line-number-at-pos top-pos) ; top-line
                        begin-column
                        1 ; initial max-len
                        1 ; initial max-int-len
                        begin-point) ; really: editing-begin-mark
    (when calctape-box
      (calctape--make-box ; (upper-left-pos lower-left-pos rightmost-column)
         top-pos
         (progn (goto-char editing-sum-mark) ; FIX: Fixes excess blank line under sum
                (rectangle-previous-line 1)
                (point))
         (+ begin-column
            calctape-op-dist
            max-len ; was: (max max-len sum-len)
            (if (zerop max-desc-len)
              0
             (+ calctape-desc-dist max-desc-len)))))))


(defun calctape--edit (op-todo &optional number-of-lines-to-delete)
  "Perform edit operation OP-TODO on a tape.
Valid values for OP-TODO are `edit' (see docstring of function
`calctape-edit') and `delete' (see docstring for function
`calctape-delete'). NUMBER-OF-LINES-TO-DELETE should be a positive
integer. It is ignored when OP-TODO is `edit'."
  (let* ((begin-point (point)) ; FIXME: Is this necessarily? See `editing-begin-mark'/
         begin-column
         (op-regex "\\(T\\)\\|\\(%?[+*/-]\\)")
         (invalid-tape-msg "calctape-edit: Not within a validly formatted tape (%s).")
         top-pos   ; beginning (operator char) of top tape line
         (editing-begin-mark (make-marker))
         line-begin-pos
         line-box-end-pos
         editing-begin-sum
         max-len
         max-int-len
         max-desc-len
         editing-sum-mark
         return-list)
    (save-mark-and-excursion
      ;; Validate current line of tape and strip box
      (unless
        (and (setq line-box-end-pos
               (search-forward
                 (car calctape-box-chars) (line-end-position) t))
             (goto-char begin-point)
             (search-backward
               (car calctape-box-chars) (line-beginning-position) t)
             (re-search-forward (calctape--line-regex) line-box-end-pos))
        (user-error invalid-tape-msg "current line"))
      (goto-char (match-beginning 1)) ; operator
      (save-mark-and-excursion
        (with-demoted-errors "Error: %s" (calctape-strip-box)))
      ;; Basic validation of tape. Establish tape's top-left boundary
      (setq line-begin-pos (line-beginning-position))
      (setq begin-column (current-column))
      (set-marker editing-begin-mark line-begin-pos)
      (set-marker-insertion-type editing-begin-mark t)
      (while (and (= (current-column) begin-column)
                  (/= 1 (line-number-at-pos))
                  (looking-at op-regex))
        (rectangle-previous-line 1))
      ;; Validate / calculate tape
      (rectangle-next-line 1)
      (setq top-pos (point))
      (setq return-list
        (calctape--tabulate "0" ; initial sum
                            (line-number-at-pos top-pos) ; top-line
                            begin-column
                            1 ; initial max-len
                            1 ; initial max-int-len
                            begin-point)) ; really: editing-begin-mark
      (set-marker-insertion-type (setq editing-sum-mark (point-marker)) t)
      (setq editing-begin-sum (pop return-list))
      (setq max-len (pop return-list))
      (setq max-int-len (pop return-list))
      (setq max-desc-len (pop return-list))
      (cond
       ((eq op-todo 'edit)
         (calctape--create top-pos
                           begin-column
                           editing-begin-mark
                           editing-begin-sum
                           max-len
                           max-int-len
                           0 ; initial value for max-dec-len (it works!?)
                           max-desc-len
                           editing-sum-mark))
       ((eq op-todo 'delete)
         (calctape--delete number-of-lines-to-delete
                           top-pos
                           begin-point
                           editing-begin-mark
                           begin-column
                           max-len
                           max-desc-len
                           editing-sum-mark
                           editing-begin-sum))
      (t (error "calctape--edit: Invalid option"))))
    (goto-char editing-begin-mark)))



(defun calctape--create (&optional editing-top-pos
                                   editing-begin-col
                                   editing-begin-mark
                                   editing-begin-sum
                                   editing-max-len
                                   editing-max-int-len
                                   editing-max-dec-len
                                   editing-max-desc-len
                                   editing-sum-mark)
  "Add lines to a tape.

This function is called by interactive function `calctape-create' with
no arguments and by interactive function `calctape-edit' with all
arguments NON-NIL.

EDITING-TOP-POS is the POINT at the upper left of the entire tape, ie.
the operator character of the first line of the tape.

EDITING-BEGIN-COL is the left-most column of the tape, ie. the column
with the math operators.

EDITING-BEGIN-MARK is the POINT at which to insert the operator of the
first new tape line being added to the existing tape.

EDITING-BEGIN-SUM is the string output from function `calc-eval'
representing the sum of the tape at EDITING-BEGN-POS.

EDITING-MAX-LEN is the maximum length of all number strings above
EDITING-BEGIN-MARK.

EDITING-MAX-INT-LEN is the maximum length of all integer portions of
number strings above EDITING-BEGIN-MARK.

EDITING-MAX-DEC-LEN is the maximum length of all non-integer portions of
number strings above EDITING-BEGIN-MARK.

EDITING-MAX-DESC-LEN is the guessed maximum length of pre-existing
descriptions. This value is used by function `calctape--make-box'.

EDITING-SUM-MARK is a mark for the first character on the sum line,
ie. the tape grand total."
  (let*
      ((called-by-calctape-edit editing-top-pos)
       (num-regex       (concat "^"
                                (calctape--full-num-regex)
                                calctape--operator-regex
                                "$"))
       (num-regex-SLACK (concat "^"
                                (calctape--full-num-regex-SLACK)
                                calctape--operator-regex
                                "$"))
       ;; sub-groups of num-regex (and num-regex-SLACK
       ;;  1  signed integer
       ;;  2  decimal point and value
       ;;  3  full scientific notation exponent
       ;;  4  exponent only
       ;;  5  math operator
       (editing-top-line (line-number-at-pos editing-top-pos))
       ctrl-todo   ; NON-NIL when 'value' matches 'calctape--controls-regex'
       ctrl-string ; The control operation to perform
       (default-description "")
       (completing-read-function   ; Users often change this to an alternative that
        #'completing-read-default) ; Doesn't support arg REQUIRE-MATCH being a function
       (top-pos (or editing-top-pos; Upper-left bound of tape. Used for realignments
                    (point)))
       (sum (or editing-begin-sum "0"))         ; Tape current subtotal
       (thou-sum (calctape--delimit-num sum))   ; sum, with thousands delimiters
       (editing-sum sum)                        ; Tape current subtotal at POINT
       (editing-thou-sum thou-sum)              ; Tape current subtotal at POINT
       (sum-len 0)     ; Length of entire printed `sum'
       (sum-int-len 0) ; Length of integer portion of `sum'
       (sum-dec-len 0) ; Length of decimal portion of `sum'
       (mem "0")       ; Memory register
       (thou-mem (calctape--delimit-num mem)) ; Memory register
       temp-register  ; For swapping memory and 'current subtotal'
       (min-col (or editing-begin-col (current-column))) ; left-most column for tape
       done           ; BOOL. NON-NIL will end tape, used for '=' operation
       value          ; String matching 'num-regex', but might begin as
                      ; matching a 'calctape--controls-regex'
       thou-value     ; value, with thousands delimiters, unsafe for `calc-eval'
       thou-value-todo
       (thou-tax (calc-eval (format "(%s * 100)" (car calctape-tax-rate))))
       thou-int-len
       thou-dec-len
       operator       ; + - * / % T = see 'calctape--operator-regex'
       description    ; Optional string to annotate line of tape
       (max-desc-len  ; Longest `description', used for `calctape--make-box'
         (or editing-max-desc-len 0))
       (max-len         ; Length of entire printed 'value'
         (or editing-max-len 1))
       (max-int-len     ; Length of integer portion of 'value'
         (or editing-max-int-len 1))
       (max-dec-len     ; Length of decimal + exponent portions of 'value'
         (or editing-max-dec-len 0)))
    (when called-by-calctape-edit
      (unless editing-begin-mark
        (error "calctape-edit: Undefined editing-begin-mark"))
      (undo-boundary) ; #1 of 2 required
      (goto-char editing-begin-mark))
    (while
      (not (or done
               (string-empty-p
                 (setq thou-value
                   (completing-read
                     (format "[Memory=%s]  [Total= %s]  Value: ? "
                             thou-mem
                             (or editing-thou-sum thou-sum))
                     nil ; COLLECTION
                     nil ; PREDICATE
                     (lambda (x) ; REQUIRE-MATCH
                       (or (and (string-match calctape--controls-regex x)
                                (setq ctrl-todo t))
                           (let ((op-regex (concat calctape--operator-regex "$"))
                                 num op)
                             (setq num
                               (if (not (string-match op-regex x))
                                 x
                                (setq op (match-string 1 x))
                                (substring x 0 (match-beginning 1))))
                             (or (condition-case _err
                                   (setq value
                                     (concat (calctape--delimit-num-check num) op))
                                   (error nil))
                                 (condition-case _err
                                   (and (setq thou-value-todo (calctape--delimit-num num))
                                        (setq value x))
                                   (error nil))))))
                     nil ; INITIAL-INPUT
                     'calctape--value-history)))))
      (when thou-value-todo
        (setq thou-value thou-value-todo)
        (setq thou-value-todo nil))
      (when ctrl-todo
        (setq ctrl-todo nil)
        (setq ctrl-string (upcase thou-value))
        (cond
         ((string= ctrl-string "C")
          (cond
           (called-by-calctape-edit
            (setq sum
              (setq editing-sum editing-begin-sum))
            (setq thou-sum
              (setq editing-thou-sum (calctape--delimit-num editing-sum)))
            (setq min-col editing-begin-col)
            (setq max-desc-len editing-max-desc-len)
            (setq max-len editing-max-len)
            (setq max-int-len editing-max-int-len)
            (setq max-dec-len editing-max-dec-len)
            (undo-boundary) ; #2 of 2 required
            (undo)
            (goto-char editing-begin-mark))
           (t
            (setq editing-thou-sum
              (setq thou-sum
                (setq sum "0")))
            (setq thou-value
              (setq value "0"))
            (calctape--print-total-for-clear min-col max-len)
            (setq max-desc-len (max max-desc-len
                                    (length calctape--clear-op-description))))))
         ((string= ctrl-string "MC")
          (setq mem "0")
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-clear)))
         ((or (string= ctrl-string "M")
              (string= ctrl-string "M+"))
          (setq mem (calc-eval (format "(%s + %s)" mem sum)))
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-plus)))
         ((string= ctrl-string "M-")
          (setq mem (calc-eval (format "(%s - %s)" mem sum)))
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-minus)))
         ((string= ctrl-string "M*")
          (setq mem (calc-eval (format "(%s * %s)" mem sum)))
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-times)))
         ((string= ctrl-string "M/")
          (setq mem (calc-eval (format "(%s / %s)" mem sum)))
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-divide)))
         ((or (string= ctrl-string "MR")
              (string= ctrl-string "MR+"))
          (setq value mem)
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-current)))
         ((string= ctrl-string "MR-")
          (setq value (concat mem "-"))
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-current)))
         ((string= ctrl-string "MR*")
          (setq value (concat mem "*"))
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-current)))
         ((string= ctrl-string "MR/")
          (setq value (concat mem "/"))
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-current)))
         ((string= ctrl-string "MS")
          (setq temp-register sum)
          (setq value "0")
          (setq default-description
            (calctape--desc-fmt calctape-description-mem-swap))
          (setq sum (setq editing-sum mem))
          (setq mem temp-register))
         ((string= ctrl-string "T")
          (setq value
                (concat
                 (calc-eval (format "round( (%s * %s), 2)"
                                    (car calctape-tax-rate)
                                    sum))
                 "T"))
          (setq default-description
             (calctape--desc-fmt calctape-description-tax))))
        (setq thou-mem (calctape--delimit-num mem)))
      (unless (string= ctrl-string "C") ; "clear" operation being performed
        (and (string-match num-regex value)
             (setq operator (match-string 5 value))
             (setq value (replace-match "" nil t value 5)))
        (setq thou-value (calctape--delimit-num value))
        (when (string-match num-regex-SLACK thou-value)
          (setq max-int-len
            (max max-int-len
                 (setq thou-int-len (length (match-string 1 thou-value)))))
          (setq max-dec-len
            (max max-dec-len
                 (setq thou-dec-len
                   (+ (length (or (match-string 2 thou-value) ""))
                      (length (or (match-string 3 thou-value) ""))))))
          (setq max-len (max max-len (length thou-value))))
        (when (and operator
                   (string-match "%" operator))
          (setq operator (replace-match "" nil nil operator))
          (when (zerop (length operator))
            (setq operator "+"))
          (setq default-description
            (calctape--desc-fmt calctape-description-percent))
          (setq thou-value
            (calctape--delimit-num
              (setq value (calc-eval (format "(%s * %s / 100)" value sum))))))
        (setq sum
          (calctape--operate sum operator value))
        (setq thou-sum (calctape--delimit-num sum))
        (if (not (string-match num-regex-SLACK thou-sum))
          (error "calctape--create: Internal sum format error (%s)" sum)
         (setq sum-len (length thou-sum))
         (setq sum-int-len (length (or (match-string 1 thou-sum) "")))
         (setq sum-dec-len
           (+ (length (or (match-string 2 thou-sum) ""))
              (length (or (match-string 3 thou-sum) "")))))
        (setq editing-sum
          (calctape--operate editing-sum operator value))
        (setq editing-thou-sum (calctape--delimit-num editing-sum))
        (when (string= operator "=")
          (setq done t)
          (setq operator "+"))
        (setq description
              (or (completing-read
                    (format "[Memory=%s]  [Total= %s]  Description: ? "
                            thou-mem
                            (or editing-thou-sum thou-sum))
                    (lambda(x _y _z) x) ; collection function
                    (list default-description)
                    nil
                    default-description
                    'calctape--description-history)
                  ""))
        (setq max-desc-len (max max-desc-len (length description)))
        (calctape--print-prep min-col)
        (insert (format "%s%s%s%s%s%s"
                        (or operator "+")
                        (string-pad " " (+ calctape-op-dist
                                            (- max-int-len
                                               thou-int-len)))
                        thou-value
                        (string-pad " " (+ calctape-desc-dist
                                            (- max-dec-len
                                               thou-dec-len)))
                        description
                        (if called-by-calctape-edit "\n" "")))
        (setq default-description "")
        (if (not called-by-calctape-edit)
          (calctape--advance-line min-col)
         (calctape--tabulate editing-sum ;; ?? MAYBE: editing-begin-sum
                             editing-top-line
                             min-col
                             (max max-len
                                  sum-len)
                             (max max-int-len
                                  sum-int-len)
                             editing-begin-mark)
         (goto-char editing-begin-mark)))
      (setq ctrl-string nil)
      (calctape--perform-realignment top-pos
                                       min-col
                                       (max max-len
                                            sum-len)
                                       (max max-int-len
                                            sum-int-len)
                                       editing-sum-mark))
    ;; End of `while' loop for `completing-read' of values/descriptions
    (unless (or called-by-calctape-edit
                (= top-pos (point)))
      (calctape--print-total-line thou-sum
                                  min-col
                                  (max max-int-len
                                       sum-int-len)
                                  (max max-dec-len
                                       sum-dec-len)))
    (when calctape-box
      (calctape--make-box ; (upper-left-pos lower-left-pos rightmost-column)
         top-pos
         (if called-by-calctape-edit
           editing-sum-mark
          (+ (line-beginning-position) min-col))
         (+ min-col
            calctape-op-dist
            (max max-len sum-len)
            (if (zerop max-desc-len)
              0
             (+ calctape-desc-dist max-desc-len)))))))



;;
;;; Interactive functions:


;;;###autoload
(defun calctape-strip-box (&optional pos)
  "Remove the box surrounding the tape at POS or POINT.

Hints: You can prevent `calctape' from drawing boxes around tapes by set
customization variable `calctape-box' to NIL; You can define which
characters are used to draw boxes by modifying customization variable
`calctape-box-chars'; You can force this operation to be \"careful\" by
modifying customization variable `calctape-strip-box-carefully'."
  (interactive)
  ;; TODO: enable user input of POS
  (undo-boundary)
  (save-mark-and-excursion
    (calctape--strip-box pos))
  (undo-boundary))


;;;###autoload
(defun calctape-sum ()
  "Find and sum a pre-existing rectangle of raw numbers around POINT.
This function is NOT meant for use with a pre-existing tape! It is meant
solely for a vaguely rectangular collection of numbers. This function
ignores any prefix column of mathematical operators. In order to edit a
pre-existing tape, see function `calctape-edit'.

Unlike functions `calctape-create' and `calctape-edit', this function
does not support scientific notation."
(interactive)
(let ((start-pos (point-marker))
      num-data ; (num, num-thou, start-col, end-col desc-len)
      (sum-struct '("0" "0" 0 0 nil nil))
   ;; (sum-struct '(sum-string, sum-string-thou, max-int-len, max-dec-len, min-col, max-col))
   ;;    sum-string       :  output of function `calc-eval'
   ;;    sum-string-thou  :  output of function `calctape--delimit-num'
   ;;    max-int-len      :  maximum length of integer portions of numbers
   ;;    max-dec-len      :  maximum length of decimal portions of numbers
   ;;    min-col          :  minimum column in rectangle so far
   ;;    max-col          :  maximum column in rectangle so far
      number-of-lines    ; line of the tape
      max-int-len
      max-dec-len
      min-col
      temp-line
      upper-left-pos     ; For `calctape--make-box'
      lower-left-pos     ; For `calctape--make-box'
      (max-desc-len 0)   ; Length of longest description, for `calctape--make-box'
      (max-buf-line      (line-number-at-pos (point-max)))
      (prefix (concat "+" (string-pad "" calctape-op-dist #x20)))
      top-pos)           ; used for re-alignment
  (undo-boundary)
  (save-mark-and-excursion
  ;; PART 1: Find numbers above the current line
    (when (< 1 (setq temp-line (line-number-at-pos)))
      (rectangle-previous-line 1)
      (while (and (/= temp-line (setq temp-line (line-number-at-pos)))
                  (setq num-data (calctape--find-number-string)))
        (setq max-desc-len (max max-desc-len (nth 4 num-data)))
        (setq sum-struct (calctape--sum-update num-data sum-struct))
        (setq top-pos (point))
        (rectangle-previous-line 1)))
  ;; PART 2: Find number on current line
    (goto-char start-pos)
    (when (setq num-data (calctape--find-number-string))
      (setq max-desc-len (max max-desc-len (nth 4 num-data)))
      (setq sum-struct (calctape--sum-update num-data sum-struct))
      (unless top-pos (setq top-pos (point))))
  ;; PART 3: Find numbers on subsequent lines
    (when (> max-buf-line (setq temp-line (line-number-at-pos)))
      (rectangle-next-line 1)
      (while (and (/= temp-line (setq temp-line (line-number-at-pos)))
                  (setq num-data (calctape--find-number-string)))
        (setq max-desc-len (max max-desc-len (nth 4 num-data)))
        (setq sum-struct (calctape--sum-update num-data sum-struct))
        (unless top-pos (setq top-pos (point)))
        (rectangle-next-line 1)))
    (unless (setq min-col (nth 4 sum-struct))
      (user-error "calctape: No tape found!"))
    (when (= max-buf-line temp-line)
      (cl-incf temp-line)
      (end-of-line)
      (insert "\n"))
    (setq number-of-lines (- temp-line (line-number-at-pos top-pos) -1))
    (setq max-int-len (nth 2 sum-struct))
    (setq max-dec-len (nth 3 sum-struct))
    (goto-char top-pos)
    (forward-line 0)
    (while (< 0 (cl-decf number-of-lines))
      (cond
       (calctape-perform-realignment
         (cond
          ((< min-col (- (line-end-position) (point)))
           (forward-char min-col)
           (insert prefix))
          (t
           (end-of-line)
           (insert-char #x20 (- min-col (current-column)))
           (insert "\n")
           (backward-char (+ min-col 3)))))
       (t
         (forward-char (- min-col 2))
         (insert "+")))
      (forward-line 1))
    (when calctape-perform-realignment
      (calctape--perform-realignment top-pos
                                     min-col
                                     (+ max-int-len max-dec-len)
                                     max-int-len))
    (forward-line -1)
    (forward-char min-col)
    (calctape--advance-line min-col)
    (calctape--print-total-line (nth 1 sum-struct) ; sum-thou
                                min-col
                                max-int-len
                                max-dec-len)
    (when calctape-box
      (setq lower-left-pos (+ (line-beginning-position) min-col))
      (goto-char top-pos)
      (forward-line 0)
      (setq upper-left-pos (+ (point) min-col))
      (calctape--make-box ; (upper-left-pos lower-left-pos rightmost-column)
        upper-left-pos
        lower-left-pos
        (+ min-col
           calctape-op-dist
           (max max-int-len (length (nth 1 sum-struct)))
           (if (zerop max-desc-len)
             0
            (+ calctape-desc-dist max-desc-len))))))
  (goto-char start-pos)
  (undo-boundary)))



;;;###autoload
(defun calctape-delete (number-of-lines)
  "Delete the current line from a tape.
With a PREFIX-ARG, or programmatically NUMBER-OF-LINES, delete that many
lines, beginning on the current line. With a REGION selected, delete the
lines spanning the region."
  (interactive "p")
  (let ((return-column (current-column))
        (selected-regions (region-bounds))
        a b)
    (when (and (= number-of-lines 1)
               (region-active-p))
      (deactivate-mark)
      (unless (= 1 (length selected-regions))
        (user-error "calctape-delete: Noncontiguous regions not supported.?"))
      (setq a (max (caar selected-regions) (cdar selected-regions)))
      (setq b (min (caar selected-regions) (cdar selected-regions)))
      (setq number-of-lines (- (line-number-at-pos a)
                               (line-number-at-pos b)
                               -1))
      (goto-char b))
    (calctape--edit 'delete number-of-lines)
    (forward-char return-column)))


;;;###autoload
(defun calctape-edit ()
  "Edit a pre-existing tape.

IMPORTANT: This feature does not support tapes that include memory
recall operations, or tax calculations if the configured tax rate has
been altered.

Requires POINT to be within a rectangle consistent in format to a tape
created by functions `calctape-create' or `calctape-sum'. The function
begins by recalculating the tape. This serves to allow the user to edit
the tape outside of `calctape'. The function then prompts the user for
additions to be made after POINT, and recalculates the tape at each
entry. Exit the function gracefully by keying RETURN when prompted for a
value."
  (interactive)
  (undo-boundary)
  (let ((return-column (current-column)))
    (calctape--edit 'edit)
    (forward-char return-column))
  (undo-boundary))



;;;###autoload
(defun calctape-create ()
  "Create a tape.

  Prompts for numbers (or control operators) and their optional
  descriptions. A tape can be ended by entering no value when prompted for
  a number. At that point, the final result will be printed. The current
  running total will be displayed as part of each number prompt.

  Numbers may optionally be suffixed with basic arithmetic operators '+',
  '-', '*', '/', or any of following percentage operators: '%' or '%+'
  adds a percentage of SUM to SUM, '%-' subtracts a percentage of SUM from
  SUM, and '%*' multiplies SUM by a percentage.

  The following control operators are available at the number prompt:

  C   :: clears total only (not memory) and begins a new tape
  MC  :: clears memory only (not total)
  M   :: adds current total to memory
  M+  :: adds current total to memory
  M-  :: subtracts current total from memory
  MR  :: adds memory to current total
  MR+ :: adds memory to current total
  MR- :: subtracts memory from current total
  MS  :: swaps total with memory
  T   :: (+ (* (car `calctape-tax-rate') sum) sum)

  New York City sales tax has been chosen for the default tax rate, as a
  reward for being the most difficult one I know to manually
  enter (8.875%). See customization variable `calctape-tax-rate'."
  (interactive)
  (undo-boundary)
  (calctape--position-sanity-check)
  (calctape--create)
  (undo-boundary))


;;;###autoload
(defun calctape-qc (&optional insert)
  "Perform `quick-calc' and apply thousands delimiters to the result.
This amounts to a bit of \"feature-creep\" on the part of the `calctape'
package. Since the `calctape' package already provides the code to apply
thousands delimiters to `calc-eval' results, why not?

  With the optional PREFIX-ARG, or programmatically INSERT, insert the
  result into the current buffer, at POINT."
  (interactive "P")
  (let (captured-message
        final-output
        insert-string
        current-num ; really belongs in mapconcat lambda scope
        next)
    (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest format-args)
                   (setq captured-message
                     (apply #'format format-string format-args)))))
      (quick-calc))
    (setq final-output
      (mapconcat
        (lambda (x)
          (setq current-num
              (condition-case _err
                (calctape--delimit-num x)
                (error nil)))
          (when (and insert next)
            (setq insert-string (or current-num x))
            (setq next nil))
          (when (string= x "=>")
            (setq next t))
          (or current-num x))
        (string-split captured-message)
        " "))
    (when insert
      (insert insert-string))
    (message "%s" final-output)))



;;
;;; Conclusion:

(provide 'calctape)

;;; calctape.el ends here
